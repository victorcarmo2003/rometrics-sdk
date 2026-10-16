--!strict
-- Finds who assigns MarketplaceService.ProcessReceipt in Luau source and rewrites that assignment
-- to go through RoMetrics.wrapProcessReceipt. Pure (string in, string out), tested offline.
-- ProcessReceipt has a single owner (the last assignment wins), so the plugin never adds a second
-- one: it wraps the one the game already has.
local Receipts = {}

export type Token = {
	kind: "name" | "op" | "string" | "number",
	text: string,
	s: number, -- first byte
	e: number, -- last byte
	line: number,
}

export type Assignment = {
	form: "assign" | "function", -- `X.ProcessReceipt = expr` or `function X.ProcessReceipt(...) end`
	line: number, -- line of `ProcessReceipt`
	endLine: number,
	target: string, -- e.g. "MarketplaceService.ProcessReceipt"
	-- Byte range of the callback expression (assign) or of the whole declaration (function).
	s: number,
	e: number,
	wrapped: boolean, -- already goes through RoMetrics.wrapProcessReceipt
	tracked: boolean, -- the callback calls RoMetrics.trackReceipt itself
	preview: string, -- first line of the assignment, trimmed
}

local KEYWORD_OPEN = { ["function"] = true, ["if"] = true, ["do"] = true, ["repeat"] = true }
local KEYWORD_CLOSE = { ["end"] = true, ["until"] = true }
local BRACKET_OPEN = { ["("] = true, ["["] = true, ["{"] = true }
local BRACKET_CLOSE = { [")"] = true, ["]"] = true, ["}"] = true }
-- Tokens that keep an expression going onto the next line.
local CONTINUES = {
	["or"] = true,
	["and"] = true,
	["not"] = true,
	[".."] = true,
	["+"] = true,
	["-"] = true,
	["*"] = true,
	["/"] = true,
	["//"] = true,
	["%"] = true,
	["^"] = true,
	["=="] = true,
	["~="] = true,
	["<"] = true,
	[">"] = true,
	["<="] = true,
	[">="] = true,
	[","] = true,
	["."] = true,
	[":"] = true,
	["::"] = true,
	["="] = true,
}

-- Long bracket (`[[`, `[==[`) starting at `i`: returns the index of its last byte, or nil.
local function longBracketEnd(source: string, i: number): number?
	local equals = string.match(source, "^%[(=*)%[", i)
	if not equals then
		return nil
	end
	local close = "]" .. equals .. "]"
	local _, last = string.find(source, close, i + #equals + 2, true)
	return last or #source
end

-- Luau tokens without comments or whitespace. Good enough to find assignments and match blocks.
function Receipts.tokenize(source: string): { Token }
	local tokens: { Token } = {}
	local i = 1
	local line = 1
	local n = #source
	local function push(kind: any, s: number, e: number, startLine: number)
		table.insert(tokens, { kind = kind, text = string.sub(source, s, e), s = s, e = e, line = startLine })
	end
	local function countLines(s: number, e: number)
		local _, count = string.gsub(string.sub(source, s, e), "\n", "")
		line += count
	end
	while i <= n do
		local c = string.sub(source, i, i)
		if c == "\n" then
			line += 1
			i += 1
		elseif string.match(c, "%s") then
			i += 1
		elseif string.sub(source, i, i + 1) == "--" then
			local long = longBracketEnd(source, i + 2)
			local last = long or (string.find(source, "\n", i, true) or n + 1) - 1
			countLines(i, last)
			i = last + 1
		elseif c == "[" and string.match(source, "^%[=*%[", i) then
			local last = longBracketEnd(source, i) :: number
			push("string", i, last, line)
			countLines(i, last)
			i = last + 1
		elseif c == '"' or c == "'" or c == "`" then
			local j = i + 1
			while j <= n do
				local d = string.sub(source, j, j)
				if d == "\\" then
					j += 2
				elseif d == c then
					break
				elseif d == "\n" and c ~= "`" then
					break
				else
					j += 1
				end
			end
			local last = math.min(j, n)
			push("string", i, last, line)
			countLines(i, last)
			i = last + 1
		elseif string.match(c, "[%a_]") then
			local _, last = string.find(source, "^[%w_]+", i)
			push("name", i, last :: number, line)
			i = (last :: number) + 1
		elseif string.match(c, "%d") or (c == "." and string.match(source, "^%.%d", i)) then
			local _, last = string.find(source, "^[%w_%.]+", i)
			push("number", i, last :: number, line)
			i = (last :: number) + 1
		else
			local three = string.sub(source, i, i + 2)
			local two = string.sub(source, i, i + 1)
			if three == "..." or three == "..=" or three == "//=" then
				push("op", i, i + 2, line)
				i += 3
			elseif
				two == "=="
				or two == "~="
				or two == "<="
				or two == ">="
				or two == ".."
				or two == "::"
				or two == "->"
				or two == "//"
				or (string.sub(two, 2, 2) == "=" and string.match(c, "[%+%-%*/%%%^]"))
			then
				push("op", i, i + 1, line)
				i += 2
			else
				push("op", i, i, line)
				i += 1
			end
		end
	end
	return tokens
end

-- Index of the last token of the expression that starts at `first`.
local function expressionEnd(tokens: { Token }, first: number): number
	local depth = 0
	local index = first
	while index <= #tokens do
		local token = tokens[index]
		-- Brackets and blocks share one depth. `while`/`for` open with their `do`; `if` expressions
		-- (no `end`) are not handled.
		local opens = (token.kind == "op" and BRACKET_OPEN[token.text])
			or (token.kind == "name" and KEYWORD_OPEN[token.text])
		local closes = (token.kind == "op" and BRACKET_CLOSE[token.text])
			or (token.kind == "name" and KEYWORD_CLOSE[token.text])
		if opens then
			depth += 1
		elseif closes then
			depth -= 1
			if depth < 0 then
				return index - 1
			end
		elseif token.kind == "op" and token.text == ";" and depth == 0 then
			return index - 1
		end
		local nextToken = tokens[index + 1]
		if depth == 0 then
			if not nextToken then
				return index
			end
			if nextToken.line > token.line and not CONTINUES[token.text] then
				-- A next line starting with `(`, `.`, `:` or an operator still belongs to the expression.
				local t = nextToken.text
				local continues = nextToken.kind == "op" and t ~= "(" and t ~= "[" and CONTINUES[t] == true
				if not continues and not (nextToken.kind == "name" and (t == "or" or t == "and")) then
					return index
				end
			end
		end
		index += 1
	end
	return #tokens
end

-- Index of the `end` that closes the block opened by the token at `first`.
local function blockEnd(tokens: { Token }, first: number): number
	local depth = 0
	for index = first, #tokens do
		local token = tokens[index]
		if token.kind == "name" and KEYWORD_OPEN[token.text] then
			depth += 1
		elseif token.kind == "name" and KEYWORD_CLOSE[token.text] then
			depth -= 1
			if depth == 0 then
				return index
			end
		end
	end
	return #tokens
end

local function lineAt(source: string, position: number): string
	local lineStart = position
	while lineStart > 1 and string.sub(source, lineStart - 1, lineStart - 1) ~= "\n" do
		lineStart -= 1
	end
	local lineEnd = string.find(source, "\n", position, true) or #source + 1
	local text = string.sub(source, lineStart, lineEnd - 1)
	return (string.gsub(string.gsub(text, "^%s+", ""), "%s+$", ""))
end

local function containsName(tokens: { Token }, from: number, to: number, name: string): boolean
	for index = from, to do
		if tokens[index].kind == "name" and tokens[index].text == name then
			return true
		end
	end
	return false
end

-- Locals that hold MarketplaceService (`local MPS = game:GetService("MarketplaceService")`).
local function marketplaceAliases(source: string): { [string]: boolean }
	local aliases = { MarketplaceService = true }
	for name in string.gmatch(source, "local%s+([%a_][%w_]*)%s*=%s*game:GetService%(%s*[\"']MarketplaceService[\"']%s*%)") do
		aliases[name] = true
	end
	return aliases
end

-- Every assignment of MarketplaceService.ProcessReceipt in the source (comments and strings
-- ignored). `ShopService.ProcessReceipt = ...` on the game's own tables does not count.
function Receipts.find(source: string): { Assignment }
	local tokens = Receipts.tokenize(source)
	local aliases = marketplaceAliases(source)
	local out: { Assignment } = {}
	for index, token in tokens do
		if token.kind ~= "name" or token.text ~= "ProcessReceipt" then
			continue
		end
		local dot = tokens[index - 1]
		if not dot or dot.text ~= "." then
			continue
		end
		-- Walk back over `a.b.c` / `game:GetService("X")` to the start of the target.
		local first = index - 1 -- the dot
		while true do
			local prev = tokens[first - 1]
			if not prev then
				break
			end
			if prev.kind == "name" and not KEYWORD_OPEN[prev.text] and not KEYWORD_CLOSE[prev.text] then
				first -= 1
			elseif prev.text == ")" then
				-- A call like GetService("MarketplaceService"): jump to its callee.
				local depth = 0
				local j = first - 1
				while j >= 1 do
					if tokens[j].text == ")" then
						depth += 1
					elseif tokens[j].text == "(" then
						depth -= 1
						if depth == 0 then
							break
						end
					end
					j -= 1
				end
				local callee = tokens[j - 1]
				if not callee or callee.kind ~= "name" then
					break
				end
				first = j - 1
			else
				break
			end
			local sep = tokens[first - 1]
			if sep and (sep.text == "." or sep.text == ":") then
				first -= 1
			else
				break
			end
		end
		if tokens[first].text == "." or tokens[first].text == ":" then
			continue
		end
		local target = string.sub(source, tokens[first].s, token.e)
		if not aliases[tokens[first].text] and not string.find(target, "MarketplaceService", 1, true) then
			continue
		end
		local before = tokens[first - 1]
		local after = tokens[index + 1]
		if before and before.kind == "name" and before.text == "function" and after and after.text == "(" then
			local last = blockEnd(tokens, first - 1)
			table.insert(out, {
				form = "function",
				line = token.line,
				endLine = tokens[last].line,
				target = target,
				s = before.s,
				e = tokens[last].e,
				wrapped = false,
				tracked = containsName(tokens, first, last, "trackReceipt"),
				preview = lineAt(source, before.s),
			})
		elseif after and after.text == "=" then
			local exprFirst = index + 2
			if exprFirst > #tokens then
				continue
			end
			local last = expressionEnd(tokens, exprFirst)
			table.insert(out, {
				form = "assign",
				line = token.line,
				endLine = tokens[last].line,
				target = target,
				s = tokens[exprFirst].s,
				e = tokens[last].e,
				wrapped = containsName(tokens, exprFirst, math.min(last, exprFirst + 3), "wrapProcessReceipt"),
				tracked = containsName(tokens, exprFirst, last, "trackReceipt"),
				preview = lineAt(source, tokens[first].s),
			})
		end
	end
	return out
end

-- Name of the local that already holds the SDK (`local RoMetrics = require(...RoMetrics...)`).
function Receipts.sdkVariable(source: string): string?
	for _, line in string.split(source, "\n") do
		local name, path = string.match(line, "^%s*local%s+([%a_][%w_]*)%s*=%s*require%s*%((.-)%)")
		if name and path and string.find(string.lower(path), "rometrics", 1, true) then
			return name
		end
	end
	return nil
end

-- Rewrites one assignment so the callback goes through `<sdk>.wrapProcessReceipt`. The decision the
-- game returns is unchanged; only PurchaseGranted is recorded as a sale.
function Receipts.wrap(source: string, assignment: Assignment, sdk: string): string
	local before = string.sub(source, 1, assignment.s - 1)
	local after = string.sub(source, assignment.e + 1)
	local middle = string.sub(source, assignment.s, assignment.e)
	if assignment.form == "assign" then
		return `{before}{sdk}.wrapProcessReceipt({middle}){after}`
	end
	-- `function X.ProcessReceipt(args) body end` -> `X.ProcessReceipt = sdk.wrap(function(args) body end)`
	local rewritten = string.gsub(middle, "^function%s+(.-ProcessReceipt)%s*%(", function(target: string)
		return `{target} = {sdk}.wrapProcessReceipt(function(`
	end, 1)
	return `{before}{rewritten}){after}`
end

-- Diff -------------------------------------------------------------------------------------------

export type DiffLine = { kind: "same" | "add" | "remove" | "gap", text: string, line: number? }

-- Line diff for previews (LCS over the lines between the common prefix and suffix). Unchanged
-- runs longer than `context` lines on each side of a change collapse into a "gap" line.
function Receipts.diff(old: string, new: string, context: number?): { DiffLine }
	local a = string.split(old, "\n")
	local b = string.split(new, "\n")
	local ctx = context or 2
	local prefix = 0
	while prefix < #a and prefix < #b and a[prefix + 1] == b[prefix + 1] do
		prefix += 1
	end
	local suffix = 0
	while suffix < #a - prefix and suffix < #b - prefix and a[#a - suffix] == b[#b - suffix] do
		suffix += 1
	end
	-- LCS table over the middle window (n x m).
	local n, m = #a - prefix - suffix, #b - prefix - suffix
	local lcs: { { number } } = {}
	for i = n + 1, 1, -1 do
		local row = table.create(m + 1, 0)
		local below = lcs[i + 1]
		if i <= n then
			for j = m, 1, -1 do
				if a[prefix + i] == b[prefix + j] then
					row[j] = (if below then below[j + 1] else 0) + 1
				else
					row[j] = math.max(if below then below[j] else 0, row[j + 1] or 0)
				end
			end
		end
		lcs[i] = row
	end
	local ops: { DiffLine } = {}
	for i = 1, prefix do
		table.insert(ops, { kind = "same", text = a[i], line = i })
	end
	local i, j = 1, 1
	while i <= n or j <= m do
		if i <= n and j <= m and a[prefix + i] == b[prefix + j] then
			table.insert(ops, { kind = "same", text = b[prefix + j], line = prefix + j })
			i += 1
			j += 1
		elseif i <= n and (j > m or ((lcs[i + 1] or {})[j] or 0) >= (lcs[i][j + 1] or 0)) then
			-- Removals first, so a changed line reads "− old" then "+ new".
			table.insert(ops, { kind = "remove", text = a[prefix + i], line = prefix + i })
			i += 1
		else
			table.insert(ops, { kind = "add", text = b[prefix + j], line = prefix + j })
			j += 1
		end
	end
	for k = #b - suffix + 1, #b do
		table.insert(ops, { kind = "same", text = b[k], line = k })
	end
	-- Keep `ctx` unchanged lines around each change.
	local keep: { boolean } = {}
	for index, op in ops do
		if op.kind ~= "same" then
			for k = math.max(1, index - ctx), math.min(#ops, index + ctx) do
				keep[k] = true
			end
		end
	end
	local out: { DiffLine } = {}
	local skipped = false
	for index, op in ops do
		if keep[index] then
			if skipped then
				table.insert(out, { kind = "gap", text = "…" })
				skipped = false
			end
			table.insert(out, op)
		else
			skipped = true
		end
	end
	if skipped then
		table.insert(out, { kind = "gap", text = "…" })
	end
	if out[1] and out[1].kind ~= "gap" and not keep[1] then
		table.insert(out, 1, { kind = "gap", text = "…" })
	end
	return out
end

return Receipts

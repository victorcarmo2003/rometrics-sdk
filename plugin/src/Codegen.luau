--!strict
-- Code for the "Medir" assistants: one RoMetrics call built from form fields, and its insertion at
-- a line of an existing script. Pure (tested offline).
local Registry = require(script.Parent.Registry)

local Codegen = {}

local quote = Registry.quote

-- Values typed by the user, read like Luau: "quoted" = fixed text; numbers/true/false as is; a
-- variable or simple expression (`price`, `player.Name`, `coins - price`) = code from the game.
-- Anything else (plain words with spaces) becomes text.
function Codegen.value(text: string?, fallback: string): string
	local trimmed = string.gsub(string.gsub(text or "", "^%s+", ""), "%s+$", "")
	if trimmed == "" then
		return fallback
	end
	if string.match(trimmed, '^".*"$') or string.match(trimmed, "^'.*'$") then
		return quote(string.sub(trimmed, 2, -2))
	end
	if tonumber(trimmed) ~= nil or trimmed == "true" or trimmed == "false" or trimmed == "nil" then
		return trimmed
	end
	local codeLike = string.match(trimmed, "^[%a_#][%w_%.:%(%)%[%]%+%-%*/%%#\"' ,]*$") ~= nil
	if codeLike and (not string.find(trimmed, " ") or string.find(trimmed, "[%+%-%*/%%%(]")) then
		return trimmed
	end
	return quote(trimmed)
end

-- Keeps only identifier-like input for variable names (player variable, receipt variable).
function Codegen.identifier(text: string?, fallback: string): string
	local trimmed = string.gsub(string.gsub(text or "", "^%s+", ""), "%s+$", "")
	if string.match(trimmed, "^[%a_][%w_%.]*$") then
		return trimmed
	end
	return fallback
end

local function propsTable(props: { { key: string, value: string } }?): string?
	if not props or #props == 0 then
		return nil
	end
	local parts = {}
	for _, prop in props do
		if prop.key ~= "" then
			local key = if string.match(prop.key, "^[%a_][%w_]*$") then prop.key else `[{quote(prop.key)}]`
			table.insert(parts, `{key} = {Codegen.value(prop.value, '""')}`)
		end
	end
	if #parts == 0 then
		return nil
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

export type CustomSpec = {
	sdk: string,
	player: string?,
	name: string,
	value: string?,
	props: { { key: string, value: string } }?,
}

function Codegen.custom(spec: CustomSpec): string
	local player = Codegen.identifier(spec.player, "player")
	local args = { player, quote(spec.name) }
	local props = propsTable(spec.props)
	local value = string.gsub(spec.value or "", "%s", "")
	if value ~= "" or props then
		table.insert(args, Codegen.value(spec.value, "nil"))
	end
	if props then
		table.insert(args, props)
	end
	return `{spec.sdk}:LogCustomEvent({table.concat(args, ", ")})`
end

export type EconomySpec = {
	sdk: string,
	player: string?,
	flow: "Source" | "Sink",
	currency: string,
	amount: string?,
	balance: string?,
	reason: string?, -- Enum.AnalyticsEconomyTransactionType name
	item: string?,
}

Codegen.TRANSACTION_TYPES = {
	{ value = "Shop", label = "Loja (comprou ou vendeu algo)" },
	{ value = "Gameplay", label = "Jogo (ganhou jogando)" },
	{ value = "ContextualPurchase", label = "Compra no meio da ação" },
	{ value = "TimedReward", label = "Recompensa de tempo (diária)" },
	{ value = "Onboarding", label = "Início do jogo / tutorial" },
	{ value = "IAP", label = "Compra com Robux (dev product)" },
}

function Codegen.economy(spec: EconomySpec): string
	local player = Codegen.identifier(spec.player, "player")
	local args = {
		player,
		`Enum.AnalyticsEconomyFlowType.{spec.flow}`,
		quote(spec.currency),
		Codegen.value(spec.amount, "0"),
		Codegen.value(spec.balance, "0"),
		quote(if spec.reason and spec.reason ~= "" then spec.reason else "Shop"),
	}
	local item = string.gsub(spec.item or "", "^%s+", "")
	if item ~= "" then
		table.insert(args, Codegen.value(spec.item, "nil"))
	end
	return `{spec.sdk}:LogEconomyEvent({table.concat(args, ", ")})`
end

export type FunnelSpec = {
	sdk: string,
	player: string?,
	funnel: string,
	step: number,
	stepName: string?,
}

function Codegen.funnel(spec: FunnelSpec): string
	local player = Codegen.identifier(spec.player, "player")
	local args = { player, quote(spec.funnel), "nil", tostring(spec.step) }
	if spec.stepName and spec.stepName ~= "" then
		table.insert(args, quote(spec.stepName))
	end
	return `{spec.sdk}:LogFunnelStepEvent({table.concat(args, ", ")})`
end

export type ProgressionSpec = {
	sdk: string,
	player: string?,
	path: string,
	status: "Start" | "Complete" | "Fail",
	level: string?,
}

function Codegen.progression(spec: ProgressionSpec): string
	local player = Codegen.identifier(spec.player, "player")
	return `{spec.sdk}:LogProgressionEvent({player}, {quote(spec.path)}, Enum.AnalyticsProgressionType.{spec.status}, {Codegen.value(
		spec.level,
		"1"
	)})`
end

function Codegen.trackReceipt(sdk: string, receipt: string?): string
	return `{sdk}.trackReceipt({Codegen.identifier(receipt, "receiptInfo")}) -- RoMetrics: records the sale (only when granted)`
end

-- Insertion ----------------------------------------------------------------------------------------

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- Whether a line opens a block, so code inserted after it goes one level deeper.
function Codegen.opensBlock(line: string): boolean
	local text = trim(string.gsub(line, "%-%-.*$", ""))
	if text == "" then
		return false
	end
	for _, suffix in { "then", "do", "else", "repeat" } do
		if text == suffix or string.match(text, "[^%w_]" .. suffix .. "$") then
			return true
		end
	end
	return string.match(text, "function%s*[%w_%.:]*%s*%b()[^%(%)]*$") ~= nil
		and not string.match(text, "[^%w_]end[%)%s,;]*$")
end

local function indentOf(line: string): string
	return string.match(line, "^[ \t]*") or ""
end

-- Adds header lines missing from `lines` (after `--!` directives and existing services/requires).
-- Returns how many lines were added and where.
local function addHeader(lines: { string }, header: { string }): (number, number)
	local present: { [string]: boolean } = {}
	local insertAt = 0
	for index, line in lines do
		local trimmed = trim(line)
		present[trimmed] = true
		if string.match(trimmed, "^%-%-!") then
			insertAt = math.max(insertAt, index)
		elseif
			string.match(line, "^local [%w_]+ = game:GetService%(")
			or string.match(line, "^local [%w_]+ = require%(")
		then
			insertAt = index
		end
	end
	local added = 0
	for _, line in header do
		if not present[line] then
			added += 1
			table.insert(lines, insertAt + added, line)
		end
	end
	return added, insertAt
end

-- Adds the missing header lines to a whole source (used when wrapping ProcessReceipt).
function Codegen.withHeader(source: string, header: { string }): string
	local lines = string.split(source, "\n")
	addHeader(lines, header)
	return table.concat(lines, "\n")
end

-- Inserts `code` after line `afterLine` (1-based; nil = end of script) with that line's indentation
-- (one level deeper when the line opens a block; a blank line is replaced). Missing header lines go
-- to the top. Returns the new source and the line where the code starts.
function Codegen.insert(source: string, header: { string }, code: string, afterLine: number?): (string, number)
	local lines = if source == "" then {} else string.split(source, "\n")
	local at: number
	if afterLine ~= nil and afterLine >= #lines then
		-- Past the end (or on trailing blank lines): append like "end of script".
		while #lines > 0 and trim(lines[#lines]) == "" do
			table.remove(lines)
		end
		if afterLine > #lines then
			afterLine = nil
		end
	elseif afterLine == nil then
		while #lines > 0 and trim(lines[#lines]) == "" do
			table.remove(lines)
		end
	end
	local codeLines = string.split(code, "\n")
	if afterLine == nil then
		if #lines > 0 then
			table.insert(lines, "")
		end
		at = #lines + 1
		for offset, line in codeLines do
			table.insert(lines, at + offset - 1, line)
		end
	else
		local target = lines[afterLine] or ""
		local indent: string
		if trim(target) == "" then
			-- Blank line: take the indentation of the nearest code line above.
			local above = ""
			for i = afterLine - 1, 1, -1 do
				if trim(lines[i]) ~= "" then
					above = lines[i]
					break
				end
			end
			indent = indentOf(above) .. (if Codegen.opensBlock(above) then "\t" else "")
			table.remove(lines, afterLine)
			at = afterLine
		else
			indent = indentOf(target) .. (if Codegen.opensBlock(target) then "\t" else "")
			at = afterLine + 1
		end
		for offset, line in codeLines do
			table.insert(lines, at + offset - 1, if line == "" then "" else indent .. line)
		end
	end
	local added, headerAt = addHeader(lines, header)
	if headerAt < at then
		at += added
	end
	local merged = table.concat(lines, "\n")
	if not string.match(merged, "\n$") then
		merged ..= "\n"
	end
	return merged, at
end

return Codegen

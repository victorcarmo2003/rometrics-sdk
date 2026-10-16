--!strict
-- Finds RoMetrics calls with literal event names in Luau source. Heuristic (pattern based): the
-- name must be a string literal; earlier arguments must sit on the same line and contain no commas.

local ScriptScan = {}

export type Usage = {
	method: string,
	kind: "custom" | "funnel" | "progression" | "economy",
	name: string,
	line: number,
}

-- `prefixArgs` = number of arguments before the name.
local METHODS: { { method: string, kind: any, prefixArgs: number } } = {
	{ method = "LogCustomEvent", kind = "custom", prefixArgs = 1 },
	{ method = "track", kind = "custom", prefixArgs = 0 },
	{ method = "LogFunnelStepEvent", kind = "funnel", prefixArgs = 1 },
	{ method = "LogProgressionEvent", kind = "progression", prefixArgs = 1 },
	{ method = "LogEconomyEvent", kind = "economy", prefixArgs = 2 },
}

local function patternFor(method: string, prefixArgs: number): string
	-- `[:%.]` keeps `track` from matching identifiers like `backtrack(`.
	local head = if method == "track" then "[:%.]track" else method
	local pattern = head .. "%s*%(%s*"
	for _ = 1, prefixArgs do
		pattern ..= "[^,\n]-,%s*"
	end
	return pattern .. "([\"'])([^\"'\n]+)%1"
end

local function lineAt(position: number, cache: { number }): number
	-- cache[i] = position of the i-th newline
	local line = 1
	for _, newline in cache do
		if newline < position then
			line += 1
		else
			break
		end
	end
	return line
end

function ScriptScan.scan(source: string): { Usage }
	local newlines: { number } = {}
	local start = 1
	while true do
		local found = string.find(source, "\n", start, true)
		if not found then
			break
		end
		table.insert(newlines, found)
		start = found + 1
	end
	local usages: { Usage } = {}
	for _, spec in METHODS do
		local pattern = patternFor(spec.method, spec.prefixArgs)
		local init = 1
		while true do
			local first, last, _, name = string.find(source, pattern, init)
			if not first then
				break
			end
			table.insert(usages, {
				method = spec.method,
				kind = spec.kind,
				name = name :: string,
				line = lineAt(first :: number, newlines),
			})
			init = (last :: number) + 1
		end
	end
	table.sort(usages, function(a, b)
		return a.line < b.line
	end)
	return usages
end

return ScriptScan

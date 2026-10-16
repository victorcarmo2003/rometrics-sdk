--!strict
-- Ready-made code snippets. Pure: every snippet returns `{ header, body }` where `header` holds
-- the `local X = ...` lines the body needs (merged without duplicates on insertion).
local Names = require(script.Parent.Names)
local Registry = require(script.Parent.Registry)

local Snippets = {}

export type Context = {
	sdkPath: string, -- e.g. "ReplicatedStorage.Packages.RoMetrics"
	secretName: string,
	endpoint: string,
	event: Registry.EventDef?,
}

export type Output = { header: { string }, body: string }

export type Snippet = {
	id: string,
	title: string,
	description: string,
	kind: Registry.Kind?, -- event kind the snippet needs (nil = no event)
	scriptName: string, -- name for a new Script
	build: (ctx: Context) -> Output,
}

local quote = Registry.quote

local function isIdentifier(s: string): boolean
	return string.match(s, "^[%a_][%w_]*$") ~= nil
end

-- "ReplicatedStorage.Packages.RoMetrics" -> service "ReplicatedStorage", expression for require().
function Snippets.requireParts(sdkPath: string): (string, string)
	local segments = string.split(sdkPath, ".")
	local service = segments[1]
	if not service or service == "" or not isIdentifier(service) then
		service = "ReplicatedStorage"
		segments = { "ReplicatedStorage", "Packages", "RoMetrics" }
	end
	local expr = service
	for i = 2, #segments do
		local segment = segments[i]
		expr ..= if isIdentifier(segment) then "." .. segment else `[{quote(segment)}]`
	end
	return service, expr
end

local function sdkHeader(ctx: Context): { string }
	local service, expr = Snippets.requireParts(ctx.sdkPath)
	return {
		`local {service} = game:GetService({quote(service)})`,
		`local RoMetrics = require({expr})`,
	}
end

local function withExtra(header: { string }, extra: { string }): { string }
	local out = table.clone(extra)
	for _, line in header do
		if not table.find(out, line) then
			table.insert(out, line)
		end
	end
	return out
end

local function sampleValue(propType: string): string
	if propType == "number" then
		return "0"
	elseif propType == "boolean" then
		return "false"
	end
	return '""'
end

local function propsTable(event: Registry.EventDef?): string
	if not event or #event.props == 0 then
		return "nil"
	end
	local parts = {}
	for _, prop in event.props do
		local key = if isIdentifier(prop.key) then prop.key else `[{quote(prop.key)}]`
		table.insert(parts, `{key} = {sampleValue(prop.type)}`)
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

local function eventName(ctx: Context, fallback: string): string
	return if ctx.event then ctx.event.name else fallback
end

Snippets.list = {} :: { Snippet }

table.insert(Snippets.list, {
	id = "setup",
	title = "Setup (init + Secret)",
	description = "Script de servidor: RoMetrics.init com a chave do Secrets Store e ProcessReceipt embrulhado.",
	kind = nil,
	scriptName = "RoMetricsSetup",
	build = function(ctx: Context): Output
		local header = withExtra(sdkHeader(ctx), {
			'local HttpService = game:GetService("HttpService")',
			'local MarketplaceService = game:GetService("MarketplaceService")',
			'local RunService = game:GetService("RunService")',
		})
		local body = table.concat({
			"-- Live servers: Secret from Creator Hub > experience > Secrets.",
			"-- Local Studio playtests can't read it (unless added under File > Experience Settings >",
			"-- Security > Local Secrets): paste a dev/test key below. Never put a production key in code.",
			'local STUDIO_KEY = ""',
			"local ok, key = pcall(function()",
			`\treturn HttpService:GetSecret({quote(ctx.secretName)})`,
			"end)",
			"local isStudio = RunService:IsStudio()",
			"",
			"RoMetrics.init({",
			'\tkey = if ok then key elseif isStudio and STUDIO_KEY ~= "" then STUDIO_KEY else nil,',
			`\tendpoint = {quote(ctx.endpoint)},`,
			"\tdebug = isStudio,",
			"\tenabledInStudio = true, -- false to stop sending while play-testing",
			"})",
			"",
			"MarketplaceService.ProcessReceipt = RoMetrics.wrapProcessReceipt(function(receiptInfo)",
			"\t-- Grant the developer product here; return NotProcessedYet if it could not be granted.",
			"\treturn Enum.ProductPurchaseDecision.PurchaseGranted",
			"end)",
		}, "\n")
		return { header = header, body = body }
	end,
})

table.insert(Snippets.list, {
	id = "processReceipt",
	title = "wrapProcessReceipt",
	description = "Embrulha o ProcessReceipt existente: compras de dev products são rastreadas e o retorno é preservado.",
	kind = nil,
	scriptName = "RoMetricsReceipts",
	build = function(ctx: Context): Output
		local header = withExtra(sdkHeader(ctx), { 'local MarketplaceService = game:GetService("MarketplaceService")' })
		local body = table.concat({
			"MarketplaceService.ProcessReceipt = RoMetrics.wrapProcessReceipt(function(receiptInfo)",
			'\tlocal player = game:GetService("Players"):GetPlayerByUserId(receiptInfo.PlayerId)',
			"\tif not player then",
			"\t\treturn Enum.ProductPurchaseDecision.NotProcessedYet",
			"\tend",
			"\t-- Grant receiptInfo.ProductId to the player here.",
			"\treturn Enum.ProductPurchaseDecision.PurchaseGranted",
			"end)",
		}, "\n")
		return { header = header, body = body }
	end,
})

table.insert(Snippets.list, {
	id = "custom",
	title = "LogCustomEvent",
	description = "Evento custom de um jogador (mesma assinatura do AnalyticsService).",
	kind = "custom",
	scriptName = "RoMetricsEvents_Custom",
	build = function(ctx: Context): Output
		local name = eventName(ctx, "MyEvent")
		local body = table.concat({
			`local function {Names.identifier(name)}(player: Player)`,
			`\tRoMetrics:LogCustomEvent(player, {quote(name)}, 1, {propsTable(ctx.event)})`,
			"end",
		}, "\n")
		return { header = sdkHeader(ctx), body = body }
	end,
})

table.insert(Snippets.list, {
	id = "track",
	title = "track (sem jogador)",
	description = "Evento do servidor sem jogador associado (ex.: evento global começou).",
	kind = "custom",
	scriptName = "RoMetricsEvents_Server",
	build = function(ctx: Context): Output
		local name = eventName(ctx, "ServerEvent")
		local body = `RoMetrics:track({quote(name)}, \{ value = 1, props = {propsTable(ctx.event)} })`
		return { header = sdkHeader(ctx), body = body }
	end,
})

table.insert(Snippets.list, {
	id = "funnel",
	title = "Funil (passos)",
	description = "Uma chamada LogFunnelStepEvent por passo, na ordem do registro.",
	kind = "funnel",
	scriptName = "RoMetricsFunnel",
	build = function(ctx: Context): Output
		local event = ctx.event
		local name = eventName(ctx, "Onboarding")
		local steps: { Registry.StepDef } = if event and #event.steps > 0
			then event.steps
			else { { name = "Step1" }, { name = "Step2" } }
		local lines = {
			"-- One funnelSessionId per attempt; nil for one-time funnels (onboarding).",
			`local {Names.identifier(name)}Steps = \{`,
		}
		for index, step in steps do
			table.insert(lines, `\t{Names.identifier(step.name)} = {index},`)
		end
		table.insert(lines, "}")
		table.insert(lines, "")
		table.insert(
			lines,
			`local function {Names.identifier(name)}Step(player: Player, step: number, stepName: string, funnelSessionId: string?)`
		)
		table.insert(lines, `\tRoMetrics:LogFunnelStepEvent(player, {quote(name)}, funnelSessionId, step, stepName)`)
		table.insert(lines, "end")
		table.insert(lines, "")
		for index, step in steps do
			local via = if step.event then ` -- reached via {step.event}` else ""
			table.insert(lines, `-- {Names.identifier(name)}Step(player, {index}, {quote(step.name)}){via}`)
		end
		return { header = sdkHeader(ctx), body = table.concat(lines, "\n") }
	end,
})

table.insert(Snippets.list, {
	id = "progression",
	title = "Progressão",
	description = "Start / Complete / Fail de um caminho de progressão (níveis, fases).",
	kind = "progression",
	scriptName = "RoMetricsProgression",
	build = function(ctx: Context): Output
		local name = eventName(ctx, "Level")
		local id = Names.identifier(name)
		local body = table.concat({
			`local function {id}Started(player: Player, level: number)`,
			`\tRoMetrics:LogProgressionEvent(player, {quote(name)}, Enum.AnalyticsProgressionType.Start, level)`,
			"end",
			"",
			`local function {id}Completed(player: Player, level: number)`,
			`\tRoMetrics:LogProgressionEvent(player, {quote(name)}, Enum.AnalyticsProgressionType.Complete, level)`,
			"end",
			"",
			`local function {id}Failed(player: Player, level: number)`,
			`\tRoMetrics:LogProgressionEvent(player, {quote(name)}, Enum.AnalyticsProgressionType.Fail, level)`,
			"end",
		}, "\n")
		return { header = sdkHeader(ctx), body = body }
	end,
})

table.insert(Snippets.list, {
	id = "economy",
	title = "Economia (source/sink)",
	description = "Entrada e saída de moeda; o nome do evento é o tipo de moeda.",
	kind = "economy",
	scriptName = "RoMetricsEconomy",
	build = function(ctx: Context): Output
		local name = eventName(ctx, "Coins")
		local id = Names.identifier(name)
		local body = table.concat({
			`local function {id}Earned(player: Player, amount: number, balance: number, transactionType: string)`,
			`\tRoMetrics:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Source, {quote(name)}, amount, balance, transactionType)`,
			"end",
			"",
			`local function {id}Spent(player: Player, amount: number, balance: number, transactionType: string, itemSku: string?)`,
			`\tRoMetrics:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Sink, {quote(name)}, amount, balance, transactionType, itemSku)`,
			"end",
		}, "\n")
		return { header = sdkHeader(ctx), body = body }
	end,
})

function Snippets.get(id: string): Snippet?
	for _, snippet in Snippets.list do
		if snippet.id == id then
			return snippet
		end
	end
	return nil
end

function Snippets.render(output: Output): string
	return table.concat(output.header, "\n") .. "\n\n" .. output.body .. "\n"
end

-- Merges a snippet into existing source: header lines already present are skipped; new header
-- lines go after the last existing top-level `local ... = game:GetService/require` line (or at the
-- top, after `--!strict`), and the body is appended at the end.
function Snippets.merge(source: string, output: Output): string
	local lines = string.split(source, "\n")
	local present: { [string]: boolean } = {}
	local insertAt = 0
	for index, line in lines do
		local trimmed = string.gsub(line, "%s+$", "")
		present[trimmed] = true
		if string.match(trimmed, "^%-%-!") then
			insertAt = math.max(insertAt, index)
		elseif
			string.match(trimmed, "^local [%w_]+ = game:GetService%(")
			or string.match(trimmed, "^local [%w_]+ = require%(")
		then
			insertAt = index
		end
	end
	local missing = {}
	for _, line in output.header do
		if not present[line] then
			table.insert(missing, line)
		end
	end
	for offset, line in missing do
		table.insert(lines, insertAt + offset, line)
	end
	local merged = table.concat(lines, "\n")
	merged = string.gsub(merged, "%s+$", "")
	if merged ~= "" then
		merged ..= "\n\n"
	end
	return merged .. output.body .. "\n"
end

return Snippets

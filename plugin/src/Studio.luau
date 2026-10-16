--!strict
-- Place IO: registry module, script sources/usages, snippet insertion, selection, HTTP check.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptEditorService = game:GetService("ScriptEditorService")
local Selection = game:GetService("Selection")
local ServerScriptService = game:GetService("ServerScriptService")

local Lint = require(script.Parent.Lint)
local Receipts = require(script.Parent.Receipts)
local Registry = require(script.Parent.Registry)
local ScriptScan = require(script.Parent.ScriptScan)
local Snippets = require(script.Parent.Snippets)
local Tagging = require(script.Parent.Tagging)

local Studio = {}

local SCANNED_SERVICES = {
	"Workspace",
	"ReplicatedFirst",
	"ReplicatedStorage",
	"ServerScriptService",
	"ServerStorage",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
}

-- Registry ----------------------------------------------------------------------------------------

function Studio.registryModule(): ModuleScript?
	local module = ReplicatedStorage:FindFirstChild(Registry.MODULE_NAME)
	if module and module:IsA("ModuleScript") then
		return module
	end
	return nil
end

function Studio.loadRegistry(): (Registry.Registry, { string }, boolean)
	local module = Studio.registryModule()
	if not module then
		return Registry.empty(), {}, false
	end
	local registry, notes = Registry.read(module)
	return registry, notes, true
end

local function setSource(container: LuaSourceContainer, source: string)
	local ok = pcall(function()
		ScriptEditorService:UpdateSourceAsync(container, function()
			return source
		end)
	end)
	if not ok then
		(container :: any).Source = source
	end
end

local function getSource(container: LuaSourceContainer): string
	local ok, source = pcall(function()
		return ScriptEditorService:GetEditorSource(container)
	end)
	if ok and type(source) == "string" then
		return source
	end
	local okRaw, raw = pcall(function()
		return (container :: any).Source
	end)
	return if okRaw and type(raw) == "string" then raw else ""
end
Studio.getSource = getSource

-- Writes the registry module (creating it when missing). Call inside Tagging.record.
function Studio.writeRegistry(registry: Registry.Registry)
	local module = Studio.registryModule()
	if not module then
		local created = Instance.new("ModuleScript")
		created.Name = Registry.MODULE_NAME
		created.Parent = ReplicatedStorage
		module = created
	end
	setSource(module :: ModuleScript, Registry.serialize(registry))
end

-- Scripts -----------------------------------------------------------------------------------------

function Studio.scripts(): { LuaSourceContainer }
	local out = {}
	for _, serviceName in SCANNED_SERVICES do
		local ok, service = pcall(function()
			return game:GetService(serviceName :: any)
		end)
		if ok and service then
			for _, descendant in service:GetDescendants() do
				if descendant:IsA("LuaSourceContainer") and descendant.Name ~= Registry.MODULE_NAME then
					table.insert(out, descendant)
				end
			end
		end
	end
	return out
end

function Studio.usages(): { Lint.ScriptUsage }
	local out: { Lint.ScriptUsage } = {}
	for _, container in Studio.scripts() do
		local source = getSource(container)
		-- Cheap prefilter: skip scripts that never mention the SDK API.
		if string.find(source, "RoMetrics", 1, true) or string.find(source, "Log", 1, true) then
			for _, usage in ScriptScan.scan(source) do
				table.insert(out, {
					ref = container,
					path = container:GetFullName(),
					method = usage.method,
					kind = usage.kind :: string,
					name = usage.name,
					line = usage.line,
				})
			end
		end
	end
	return out
end

function Studio.taggedInfo(): { Lint.TaggedInfo }
	local out = {}
	for _, instance in Tagging.tagged() do
		table.insert(out, Tagging.describe(instance))
	end
	return out
end

local function dottedPath(instance: Instance): string
	local parts = {}
	local node: Instance? = instance
	while node and node ~= game do
		table.insert(parts, 1, node.Name)
		node = node.Parent
	end
	return table.concat(parts, ".")
end
Studio.dottedPath = dottedPath

-- Wally keeps real package sources under `_Index`; those are never the game's own code.
local function insidePackageIndex(instance: Instance): boolean
	local node = instance.Parent
	while node and node ~= game do
		if node.Name == "_Index" then
			return true
		end
		node = node.Parent
	end
	return false
end

-- The SDK ModuleScript: a `RoMetrics` module with a `Tags` child (installed by the plugin or Rojo),
-- or a Wally link module `RoMetrics` (`return require(script.Parent._Index[...])`).
function Studio.sdkModule(): ModuleScript?
	local link: ModuleScript? = nil
	for _, serviceName in { "ReplicatedStorage", "ServerScriptService", "ServerStorage" } do
		local service = game:GetService(serviceName :: any)
		for _, descendant in service:GetDescendants() do
			if
				descendant:IsA("ModuleScript")
				and descendant.Name == "RoMetrics"
				and not insidePackageIndex(descendant)
			then
				if descendant:FindFirstChild("Tags") then
					return descendant
				elseif not link and string.find(string.lower(getSource(descendant)), "rometrics", 1, true) then
					link = descendant
				end
			end
		end
	end
	return link
end

-- Dotted path of the SDK module (see sdkModule).
function Studio.detectSdkPath(): string?
	local module = Studio.sdkModule()
	return if module then dottedPath(module) else nil
end

-- True for the SDK's own scripts and package sources (never scanned as game code).
function Studio.isLibraryScript(container: Instance, sdk: Instance?): boolean
	if insidePackageIndex(container) then
		return true
	end
	return sdk ~= nil and (container == sdk or container:IsDescendantOf(sdk))
end

-- First server Script that calls RoMetrics.init (the setup script), if any.
function Studio.setupScript(): Script?
	for _, descendant in ServerScriptService:GetDescendants() do
		if descendant:IsA("Script") and string.find(getSource(descendant), "RoMetrics.init", 1, true) then
			return descendant
		end
	end
	return nil
end

-- Header lines that make `RoMetrics` available in a script, reusing the require the setup script
-- already uses (so Wally paths like ReplicatedStorage.DevPackages.RoMetrics stay right).
function Studio.sdkHeader(fallbackPath: string): { string }
	local setup = Studio.setupScript()
	if setup then
		for _, line in string.split(getSource(setup), "\n") do
			local name, path = string.match(line, "^%s*local%s+([%a_][%w_]*)%s*=%s*require%s*%((.-)%)%s*$")
			if name and path and string.find(string.lower(path), "rometrics", 1, true) then
				local root = string.match(path, "^([%a_][%w_]*)")
				local out = {}
				if root and root ~= "game" and root ~= "script" then
					table.insert(out, `local {root} = game:GetService({Registry.quote(root)})`)
				end
				table.insert(out, `local RoMetrics = require({path})`)
				return out
			end
		end
	end
	local sdk = Studio.sdkModule()
	local service, expr = Snippets.requireParts(if sdk then dottedPath(sdk) else fallbackPath)
	return { `local {service} = game:GetService({Registry.quote(service)})`, `local RoMetrics = require({expr})` }
end

-- Sales (ProcessReceipt) ---------------------------------------------------------------------------

export type ReceiptOwner = {
	script: LuaSourceContainer,
	path: string,
	source: string,
	assignment: Receipts.Assignment,
}

-- Every assignment of MarketplaceService.ProcessReceipt in server code (scripts and modules).
-- More than one means only the last to run wins: the others never see a sale.
function Studio.receiptOwners(): { ReceiptOwner }
	local sdk = Studio.sdkModule()
	local out: { ReceiptOwner } = {}
	for _, container in Studio.scripts() do
		if container:IsA("LocalScript") or Studio.isLibraryScript(container, sdk) then
			continue
		end
		if container:IsA("Script") and (container :: Script).RunContext == Enum.RunContext.Client then
			continue
		end
		local source = getSource(container)
		if string.find(source, "ProcessReceipt", 1, true) then
			for _, assignment in Receipts.find(source) do
				table.insert(
					out,
					{ script = container, path = dottedPath(container), source = source, assignment = assignment }
				)
			end
		end
	end
	return out
end

-- Replaces a script's source in one undo step.
function Studio.editSource(container: LuaSourceContainer, source: string, label: string): string?
	return Tagging.record(`RoMetrics: {label}`, function()
		setSource(container, source)
	end)
end

-- Script editor cursor -----------------------------------------------------------------------------

export type Cursor = { script: LuaSourceContainer, line: number }

local lastCursor: Cursor? = nil
local cursorListeners: { () -> () } = {}
-- Script of each watched document (a closed document no longer answers GetScript).
local documentScripts: { [any]: Instance } = setmetatable({}, { __mode = "k" }) :: any

local function setCursor(container: any, line: any)
	if typeof(container) ~= "Instance" or not container:IsA("LuaSourceContainer") or type(line) ~= "number" then
		return
	end
	local current = lastCursor
	if current and current.script == container and current.line == line then
		return
	end
	lastCursor = { script = container, line = line }
	for _, listener in cursorListeners do
		task.spawn(listener)
	end
end

local function documentScript(document: any): any
	local ok, result = pcall(function()
		if document:IsCommandBar() then
			return nil
		end
		return document:GetScript()
	end)
	return if ok then result else nil
end

local function watchDocument(document: any, connections: { RBXScriptConnection })
	local container = documentScript(document)
	if not container then
		return
	end
	documentScripts[document] = container
	local ok, connection = pcall(function()
		return document.SelectionChanged:Connect(function(line: number)
			setCursor(container, line)
		end)
	end)
	if ok and connection then
		table.insert(connections, connection)
	end
end

-- Follows the cursor of open script tabs. Returns a stop function.
function Studio.watchEditor(onChange: () -> ()): () -> ()
	local connections: { RBXScriptConnection } = {}
	table.insert(cursorListeners, onChange)
	pcall(function()
		for _, document in ScriptEditorService:GetScriptDocuments() do
			watchDocument(document, connections)
		end
		table.insert(
			connections,
			ScriptEditorService.TextDocumentDidOpen:Connect(function(document)
				watchDocument(document, connections)
				local container = documentScript(document)
				local ok, line = pcall(function()
					return (document :: any):GetSelection()
				end)
				if container and ok then
					setCursor(container, line)
				end
			end)
		)
		table.insert(
			connections,
			ScriptEditorService.TextDocumentDidClose:Connect(function(document)
				local current = lastCursor
				if current and current.script == documentScripts[document] then
					lastCursor = nil
					onChange()
				end
			end)
		)
	end)
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		local index = table.find(cursorListeners, onChange)
		if index then
			table.remove(cursorListeners, index)
		end
	end
end

-- Moves the remembered cursor (after the plugin inserts code, the next insert goes below it).
function Studio.setCursor(container: LuaSourceContainer, line: number)
	setCursor(container, line)
end

-- Where the user last put the cursor in a script tab (nil when none is known).
function Studio.cursor(): Cursor?
	local current = lastCursor
	if current and current.script.Parent == nil then
		lastCursor = nil
		return nil
	end
	return current
end

-- Selection / navigation --------------------------------------------------------------------------

function Studio.selection(): { Instance }
	return Selection:Get()
end

function Studio.select(instances: { Instance })
	pcall(function()
		Selection:Set(instances)
	end)
end

function Studio.selectedScript(): LuaSourceContainer?
	for _, instance in Selection:Get() do
		if instance:IsA("Script") or instance:IsA("ModuleScript") or instance:IsA("LocalScript") then
			return instance :: LuaSourceContainer
		end
	end
	return nil
end

function Studio.openScript(plugin: Plugin, container: Instance, line: number?)
	pcall(function()
		plugin:OpenScript(container :: LuaSourceContainer, line or 1)
	end)
end

-- Snippets ----------------------------------------------------------------------------------------

-- Merges a snippet into `target`, or creates a new Script in ServerScriptService. Undoable.
function Studio.insertSnippet(
	output: Snippets.Output,
	target: LuaSourceContainer?,
	newName: string
): (LuaSourceContainer?, string?)
	local result: LuaSourceContainer? = nil
	local err = Tagging.record("RoMetrics: inserir snippet", function()
		if target then
			setSource(target, Snippets.merge(getSource(target), output))
			result = target
		else
			local created = Instance.new("Script")
			created.Name = newName
			-- Not open in an editor yet: plain Source assignment is enough.
			local sourced: any = created
			sourced.Source = "--!strict\n" .. Snippets.render(output)
			created.Parent = ServerScriptService
			result = created
		end
	end)
	return result, err
end

-- HTTP --------------------------------------------------------------------------------------------

export type ConnectionReport = {
	universeId: number,
	placeId: number,
	sdkInstalled: boolean,
	sdkVersion: string?,
	sdkPath: string?,
	setupScript: boolean,
	endpoint: string,
	pluginVersion: string?,
}

-- What the connection test tells the dashboard about this place.
function Studio.placeReport(endpoint: string, pluginVersion: string): ConnectionReport
	local sdk = Studio.sdkModule()
	local version = if sdk then sdk:GetAttribute("RM_Version") else nil
	return {
		universeId = game.GameId,
		placeId = game.PlaceId,
		sdkInstalled = sdk ~= nil,
		sdkVersion = if type(version) == "string" then version elseif sdk then "instalado" else nil,
		sdkPath = if sdk then dottedPath(sdk) else nil,
		setupScript = Studio.setupScript() ~= nil,
		endpoint = endpoint,
		pluginVersion = pluginVersion,
	}
end

-- POST {endpoint}/v1/connection-test/{code}/events: the server queues these as server-level custom
-- events (tagged rm_test) for the code's game, as if the SDK had sent them. Returns (ok, message). Yields.
function Studio.sendTestEvents(endpoint: string, code: string, names: { string }): (boolean, string)
	local base = string.gsub(endpoint, "/+$", "")
	local clean = string.upper((string.gsub(code, "[^%w]", "")))
	if #clean ~= 6 then
		return false, "cole o código do site primeiro (ex.: K7M-Q2P)"
	end
	local events = {}
	for i, name in names do
		if i > 10 then
			break
		end
		table.insert(events, { name = name, value = 1 })
	end
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = `{base}/v1/connection-test/{string.sub(clean, 1, 3)}-{string.sub(clean, 4)}/events`,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode({ events = events }),
		})
	end)
	if not ok then
		return false, `sem resposta do servidor: {tostring(response)}`
	end
	local res = response :: any
	if res.StatusCode == 404 then
		return false, "código expirado ou inválido: gere outro no site"
	end
	if res.StatusCode == 429 then
		return false, "muitos envios seguidos: espere um minuto"
	end
	if res.StatusCode ~= 200 then
		return false, `o servidor respondeu {res.StatusCode}`
	end
	return true, `{#events} evento(s) enviado(s)`
end

-- POST {endpoint}/v1/connection-test/{code}: tells the dashboard what this place looks like.
-- Returns (ok, message, gameName?, universeMatches?, lastEventAt?). `lastEventAt` is the unix time
-- of the last event the server received for the game (nil when none, or when the server does not
-- send it). Yields.
function Studio.reportConnectionTest(
	endpoint: string,
	code: string,
	report: ConnectionReport
): (boolean, string, string?, boolean?, number?)
	local base = string.gsub(endpoint, "/+$", "")
	if not string.match(base, "^https?://[%w%.%-:]+$") then
		return false, "endereço do servidor inválido (confira o passo 2)", nil, nil
	end
	local clean = string.upper((string.gsub(code, "[^%w]", "")))
	if #clean ~= 6 then
		return false, "o código tem 6 letras/números (ex.: K7M-Q2P)", nil, nil
	end
	-- JSONEncode drops nil fields, but the API wants explicit nulls: encode field by field.
	local function value(v: any): string
		return if v == nil then "null" else HttpService:JSONEncode(v)
	end
	local parts = {}
	for _, field in
		{ "universeId", "placeId", "sdkInstalled", "sdkVersion", "sdkPath", "setupScript", "endpoint", "pluginVersion" }
	do
		table.insert(parts, `"{field}":{value((report :: any)[field])}`)
	end
	local json = "{" .. table.concat(parts, ",") .. "}"
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = `{base}/v1/connection-test/{string.sub(clean, 1, 3)}-{string.sub(clean, 4)}`,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = json,
		})
	end)
	if not ok then
		return false, `sem resposta do servidor: {tostring(response)}`, nil, nil
	end
	local res = response :: any
	if res.StatusCode == 404 then
		return false, "código expirado ou inválido: gere outro no site", nil, nil
	end
	if res.StatusCode ~= 200 then
		return false, `o servidor respondeu {res.StatusCode}`, nil, nil
	end
	local okJson, data = pcall(function()
		return HttpService:JSONDecode(res.Body)
	end)
	if not okJson or type(data) ~= "table" then
		return false, "resposta inesperada do servidor", nil, nil
	end
	local lastEventAt: number? = nil
	if type(data.lastEventAt) == "string" then
		local okDate, date = pcall(DateTime.fromIsoDate, data.lastEventAt)
		if okDate and date then
			lastEventAt = date.UnixTimestamp
		end
	end
	return true, "ok", tostring(data.gameName), data.universeMatches == true, lastEventAt
end


-- GET {endpoint}/health. Any HTTP response means the server is reachable. Yields.
function Studio.testConnection(endpoint: string): (boolean, string)
	local base = string.gsub(endpoint, "/+$", "")
	if not string.match(base, "^https?://") then
		return false, "endpoint precisa começar com http:// ou https://"
	end
	local started = os.clock()
	local ok, response = pcall(function()
		return HttpService:RequestAsync({ Url = base .. "/health", Method = "GET" })
	end)
	local ms = math.floor((os.clock() - started) * 1000)
	if not ok then
		return false, `sem resposta: {tostring(response)}`
	end
	local status = (response :: any).StatusCode
	if status >= 200 and status < 300 then
		return true, `OK ({status}, {ms} ms)`
	end
	return true, `servidor alcançável, mas /health respondeu {status} ({ms} ms)`
end

return Studio

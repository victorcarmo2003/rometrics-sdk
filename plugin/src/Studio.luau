--!strict
-- Place IO: registry module, script sources/usages, snippet insertion, selection, HTTP check.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptEditorService = game:GetService("ScriptEditorService")
local Selection = game:GetService("Selection")
local ServerScriptService = game:GetService("ServerScriptService")

local Lint = require(script.Parent.Lint)
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

-- Finds the SDK ModuleScript (a `RoMetrics` module with a `Tags` child) and returns its dotted path.
function Studio.detectSdkPath(): string?
	for _, serviceName in { "ReplicatedStorage", "ServerScriptService", "ServerStorage" } do
		local service = game:GetService(serviceName :: any)
		for _, descendant in service:GetDescendants() do
			if
				descendant:IsA("ModuleScript")
				and descendant.Name == "RoMetrics"
				and descendant:FindFirstChild("Tags")
			then
				local parts = {}
				local node: Instance? = descendant
				while node and node ~= game do
					table.insert(parts, 1, node.Name)
					node = node.Parent
				end
				return table.concat(parts, ".")
			end
		end
	end
	return nil
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

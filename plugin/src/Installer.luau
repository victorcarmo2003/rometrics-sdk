--!strict
-- One-click SDK install/update: downloads `sdk/roblox/src` from the public GitHub repo (latest
-- release tag) and rebuilds the RoMetrics ModuleScript tree in the place, Rojo-style.
-- `plan` is pure (tested offline); `install` does the HTTP and the instance work. Never throws.
local Installer = {}

-- Services are looked up lazily so the pure parts load in the offline (Lune) test runner.
local function http(): HttpService
	return game:GetService("HttpService")
end

Installer.REPO = "victorcarmo2003/rometrics-sdk"
Installer.SOURCE_DIR = "sdk/roblox/src"
Installer.MODULE_NAME = "RoMetrics"
Installer.VERSION_ATTRIBUTE = "RM_Version"
local MAX_FILES = 64
local MAX_FILE_BYTES = 200_000

export type Node = {
	name: string,
	className: "ModuleScript" | "Script" | "LocalScript" | "Folder",
	-- Path of the file holding this node's source (nil for plain folders).
	file: string?,
	children: { Node },
}

-- "Foo.server.luau" -> ("Foo", "Script"); nil when the file is not Luau.
local function classify(fileName: string): (string?, string?)
	for _, rule in
		{
			{ ".server.luau", "Script" },
			{ ".client.luau", "LocalScript" },
			{ ".luau", "ModuleScript" },
			{ ".lua", "ModuleScript" },
		}
	do
		local suffix, className = rule[1], rule[2]
		if #fileName > #suffix and string.sub(fileName, -#suffix) == suffix then
			return string.sub(fileName, 1, -#suffix - 1), className
		end
	end
	return nil, nil
end

-- Builds the instance tree for the files under `root` (repo-relative paths, any order).
-- `init.luau` turns its folder into a ModuleScript, like Rojo. Returns nil when there is no
-- root init.luau (not an SDK checkout).
function Installer.plan(paths: { string }, root: string?): Node?
	local prefix = (root or Installer.SOURCE_DIR) .. "/"
	local top: Node = { name = Installer.MODULE_NAME, className = "Folder", children = {} }
	local folders: { [string]: Node } = { [""] = top }

	local function folder(dir: string): Node
		local existing = folders[dir]
		if existing then
			return existing
		end
		local parentDir, name = string.match(dir, "^(.*)/([^/]+)$")
		local parent = folder(parentDir or "")
		local node: Node = { name = name or dir, className = "Folder", children = {} }
		table.insert(parent.children, node)
		folders[dir] = node
		return node
	end

	local sorted = table.clone(paths)
	table.sort(sorted)
	for _, path in sorted do
		if string.sub(path, 1, #prefix) == prefix then
			local rel = string.sub(path, #prefix + 1)
			local dir, fileName = string.match(rel, "^(.*)/([^/]+)$")
			dir = dir or ""
			fileName = fileName or rel
			local name, className = classify(fileName)
			if name and className then
				if name == "init" then
					local node = folder(dir)
					node.className = className :: any
					node.file = path
				else
					table.insert(folder(dir).children, {
						name = name,
						className = className :: any,
						file = path,
						children = {},
					})
				end
			end
		end
	end
	if top.className ~= "ModuleScript" then
		return nil
	end
	return top
end

-- Every file the plan needs, in a stable order.
function Installer.files(node: Node, out: { string }?): { string }
	local list = out or {}
	if node.file then
		table.insert(list, node.file)
	end
	for _, child in node.children do
		Installer.files(child, list)
	end
	return list
end

-- HTTP --------------------------------------------------------------------------------------------

local function getJson(url: string): (any, string?)
	local ok, body = pcall(function()
		return http():GetAsync(url, true)
	end)
	if not ok then
		return nil, tostring(body)
	end
	local okJson, data = pcall(function()
		return http():JSONDecode(body)
	end)
	if not okJson then
		return nil, "resposta inválida do GitHub"
	end
	return data, nil
end

-- Latest release tag (falls back to `main` when there is no release yet).
function Installer.latestTag(): (string?, string?)
	local data, err = getJson(`https://api.github.com/repos/{Installer.REPO}/releases/latest`)
	if err then
		return nil, err
	end
	local tag = if type(data) == "table" then data.tag_name else nil
	return if type(tag) == "string" and tag ~= "" then tag else "main", nil
end

local function fetchTree(ref: string): ({ string }?, string?)
	local data, err = getJson(`https://api.github.com/repos/{Installer.REPO}/git/trees/{ref}?recursive=1`)
	if err then
		return nil, err
	end
	if type(data) ~= "table" or type(data.tree) ~= "table" then
		return nil, "lista de arquivos vazia"
	end
	local paths = {}
	for _, entry in data.tree do
		if type(entry) == "table" and entry.type == "blob" and type(entry.path) == "string" then
			table.insert(paths, entry.path)
		end
	end
	return paths, nil
end

-- Install -----------------------------------------------------------------------------------------

export type Progress = (message: string) -> ()

export type Result = {
	module: ModuleScript,
	version: string,
	files: number,
	updated: boolean,
}

local function build(node: Node, sources: { [string]: string }): Instance
	local inst = Instance.new(node.className)
	inst.Name = node.name
	if node.file then
		(inst :: any).Source = sources[node.file] or ""
	end
	for _, child in node.children do
		build(child, sources).Parent = inst
	end
	return inst
end

-- Downloads the SDK and puts it at `existing`'s place (update) or ReplicatedStorage.RoMetrics.
-- `record` wraps the place edit in a ChangeHistory recording (Tagging.record). Yields.
function Installer.install(
	existing: ModuleScript?,
	record: (label: string, fn: () -> ()) -> string?,
	progress: Progress?
): (Result?, string?)
	local report = progress or function(_: string) end
	report("Buscando a versão mais recente…")
	local tag, tagErr = Installer.latestTag()
	if not tag then
		return nil, `GitHub indisponível: {tagErr}`
	end
	report(`Listando arquivos ({tag})…`)
	local paths, treeErr = fetchTree(tag)
	if not paths then
		return nil, `não foi possível listar os arquivos: {treeErr}`
	end
	local plan = Installer.plan(paths)
	if not plan then
		return nil, `o repositório não tem {Installer.SOURCE_DIR}/init.luau`
	end
	local files = Installer.files(plan)
	if #files > MAX_FILES then
		return nil, `arquivos demais ({#files}); atualização abortada`
	end

	local sources: { [string]: string } = {}
	for index, path in files do
		report(`Baixando {index}/{#files}…`)
		local ok, body = pcall(function()
			return http():GetAsync(`https://raw.githubusercontent.com/{Installer.REPO}/{tag}/{path}`, true)
		end)
		if not ok then
			return nil, `falha ao baixar {path}: {body}`
		end
		if #body > MAX_FILE_BYTES then
			return nil, `{path} é grande demais`
		end
		sources[path] = body
	end

	report("Instalando no place…")
	local module = build(plan, sources) :: ModuleScript
	module:SetAttribute(Installer.VERSION_ATTRIBUTE, tag)
	local err = record(if existing then `atualizar SDK para {tag}` else `instalar SDK {tag}`, function()
		local parent = if existing and existing.Parent then existing.Parent else game:GetService("ReplicatedStorage")
		if existing then
			existing:Destroy()
		end
		module.Parent = parent
	end)
	if err then
		module:Destroy()
		return nil, err
	end
	return { module = module, version = tag, files = #files, updated = existing ~= nil }, nil
end

return Installer

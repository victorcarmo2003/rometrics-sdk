--!strict
--[[
	Offline TestEZ-style runner (Lune). Emulates Rojo's `script` / `require(Instance)` over the
	filesystem so specs written for Studio also run headless.

		lune run plugin/tools/run-tests.luau [dir ...] [--verbose]

	Defaults to `plugin/tests` and `sdk/roblox/tests/tags` (run from the repo root).
	`game:GetService("ReplicatedStorage")` mirrors sdk/roblox/test.project.json (RoMetrics, Tests).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local task = require("@lune/task")

local verbose = false
local roots: { string } = {}
for _, arg in process.args do
	if arg == "--verbose" then
		verbose = true
	else
		table.insert(roots, arg)
	end
end
if #roots == 0 then
	roots = { "plugin/tests", "sdk/roblox/tests/tags" }
end

-- Filesystem-backed fake Instances ---------------------------------------------------------------

local SUFFIXES = { ".luau", ".server.luau", ".client.luau", ".lua" }

local function join(a: string, b: string): string
	return if a == "" then b else a .. "/" .. b
end

local function dirname(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or ""
end

local function basename(path: string): string
	return string.match(path, "([^/]*)$") or path
end

local nodeCache: { [string]: any } = {}
-- Rojo mounts these trees under ReplicatedStorage (test.project.json).
local MOUNTED_IN_REPLICATED_STORAGE = { ["sdk/roblox/src"] = true, ["sdk/roblox/tests"] = true }
local replicatedStorage: any
local nodeMeta: any = {}

-- `path` is the instance path without extension (e.g. "sdk/roblox/src/Tags" or a directory).
local function node(path: string): any
	local cached = nodeCache[path]
	if cached then
		return cached
	end
	local created = setmetatable({ __path = path }, nodeMeta)
	nodeCache[path] = created
	return created
end

-- Lune's fs calls yield, and metamethods cannot yield: index the trees up front.
local knownFiles: { [string]: boolean } = {}
local knownDirs: { [string]: boolean } = {}
local function indexTree(dir: string)
	if not fs.isDir(dir) then
		return
	end
	knownDirs[dir] = true
	for _, entry in fs.readDir(dir) do
		local path = join(dir, entry)
		if fs.isDir(path) then
			if entry ~= "node_modules" and entry ~= ".git" then
				indexTree(path)
			end
		else
			knownFiles[path] = true
		end
	end
end
for _, dir in { "sdk/roblox", "plugin" } do
	indexTree(dir)
end

local function moduleFile(path: string): string?
	if knownDirs[path] then
		for _, suffix in SUFFIXES do
			local candidate = path .. "/init" .. suffix
			if knownFiles[candidate] then
				return candidate
			end
		end
		return nil
	end
	for _, suffix in SUFFIXES do
		if knownFiles[path .. suffix] then
			return path .. suffix
		end
	end
	return nil
end

local function exists(path: string): boolean
	return knownDirs[path] == true or moduleFile(path) ~= nil
end

nodeMeta.__index = function(self: any, key: string): any
	local path = rawget(self, "__path")
	if key == "Parent" then
		if MOUNTED_IN_REPLICATED_STORAGE[path] then
			return replicatedStorage
		end
		return node(dirname(path))
	elseif key == "Name" then
		return basename(path)
	elseif key == "FindFirstChild" then
		return function(_: any, name: string)
			local child = join(path, name)
			return if exists(child) then node(child) else nil
		end
	elseif key == "WaitForChild" then
		return function(_: any, name: string)
			return node(join(path, name))
		end
	elseif key == "GetFullName" then
		return function()
			return path
		end
	end
	local child = join(path, key)
	if not exists(child) then
		error(`{key} is not a valid member of {path}`, 2)
	end
	return node(child)
end
nodeMeta.__tostring = function(self: any): string
	return rawget(self, "__path")
end

-- Fake game ---------------------------------------------------------------------------------------

replicatedStorage = setmetatable({}, {
	__index = function(_, key: string): any
		if key == "RoMetrics" then
			return node("sdk/roblox/src")
		elseif key == "Tests" then
			return node("sdk/roblox/tests")
		elseif key == "FindFirstChild" then
			return function()
				return nil
			end
		end
		error(`{key} is not a valid member of ReplicatedStorage`, 2)
	end,
})

local game = {
	GetService = function(_: any, name: string): any
		if name == "ReplicatedStorage" then
			return replicatedStorage
		elseif name == "RunService" then
			return {
				IsStudio = function()
					return true
				end,
				IsServer = function()
					return true
				end,
			}
		end
		error(`service {name} is not available in the offline runner`, 2)
	end,
}

-- Module loading ------------------------------------------------------------------------------------

local warnings: { string } = {}
local moduleCache: { [string]: any } = {}
local loadModule: (target: any) -> any

local function makeEnv(scriptNode: any): { [string]: any }
	return {
		script = scriptNode,
		game = game,
		require = function(target: any): any
			if type(target) == "string" then
				return require(target)
			end
			return loadModule(target)
		end,
		warn = function(...: any)
			local parts = {}
			for i = 1, select("#", ...) do
				table.insert(parts, tostring((select(i, ...))))
			end
			table.insert(warnings, table.concat(parts, " "))
			if verbose then
				print("[warn]", ...)
			end
		end,
		print = function(...: any)
			if verbose then
				print(...)
			end
		end,
		typeof = function(value: any): string
			return type(value)
		end,
		task = task,
	}
end

local function run(file: string, scriptNode: any, extraEnv: { [string]: any }?): any
	local source = fs.readFile(file)
	local env = makeEnv(scriptNode)
	if extraEnv then
		for key, value in extraEnv do
			env[key] = value
		end
	end
	local chunk = luau.load(source, { debugName = file, environment = env })
	return chunk()
end

loadModule = function(target: any): any
	local path = rawget(target, "__path")
	if type(path) ~= "string" then
		error("require: not a module node", 2)
	end
	local cached = moduleCache[path]
	if cached ~= nil then
		return cached.value
	end
	local file = moduleFile(path)
	if not file then
		error(`require: no module at {path}`, 2)
	end
	local value = run(file, target)
	moduleCache[path] = { value = value }
	return value
end

-- TestEZ subset ------------------------------------------------------------------------------------

local function expect(actual: any): any
	local negated = false
	local expectation: any = {}
	local function check(pass: boolean, message: string)
		if negated then
			pass = not pass
			message = "not " .. message
		end
		if not pass then
			error(`expectation failed: {message}`, 3)
		end
	end
	local chain: any
	chain = setmetatable({}, {
		__index = function(_, key: string): any
			if key == "to" or key == "be" then
				return chain
			elseif key == "never" then
				negated = not negated
				return chain
			end
			return expectation[key]
		end,
	})
	expectation.equal = function(expected: any)
		check(actual == expected, `expected {tostring(expected)}, got {tostring(actual)}`)
	end
	expectation.ok = function()
		check(actual ~= nil and actual ~= false, `expected truthy, got {tostring(actual)}`)
	end
	expectation.a = function(typeName: string)
		check(type(actual) == typeName, `expected a {typeName}, got {type(actual)}`)
	end
	expectation.near = function(expected: number, limit: number?)
		check(math.abs(actual - expected) <= (limit or 1e-7), `expected ~{expected}, got {tostring(actual)}`)
	end
	expectation.throw = function(substring: string?)
		local ok, err = pcall(actual)
		local matches = not ok and (substring == nil or string.find(tostring(err), substring, 1, true) ~= nil)
		check(matches, `expected function to throw{if substring then " '" .. substring .. "'" else ""}`)
	end
	return chain
end

type TestCase = { name: string, fn: () -> () }
local passed, failed = 0, 0
local failures: { string } = {}

local function runSpec(file: string, scriptNode: any)
	local stack: { string } = {}
	local cases: { TestCase } = {}
	local beforeEachStack: { { () -> () } } = { {} }
	local function describe(name: string, fn: () -> ())
		table.insert(stack, name)
		table.insert(beforeEachStack, {})
		fn()
		table.remove(beforeEachStack)
		table.remove(stack)
	end
	local function it(name: string, fn: () -> ())
		local hooks: { () -> () } = {}
		for _, level in beforeEachStack do
			for _, hook in level do
				table.insert(hooks, hook)
			end
		end
		table.insert(cases, {
			name = table.concat(stack, " > ") .. " > " .. name,
			fn = function()
				for _, hook in hooks do
					hook()
				end
				fn()
			end,
		})
	end
	local function beforeEach(fn: () -> ())
		table.insert(beforeEachStack[#beforeEachStack], fn)
	end
	local ok, specFn = pcall(run, file, scriptNode, {
		describe = describe,
		it = it,
		expect = expect,
		beforeEach = beforeEach,
		-- Runner-only helpers: specs use them to prove generated code parses and evaluates.
		luauCompile = function(source: string)
			luau.compile(source)
		end,
		luauEval = function(source: string): any
			return luau.load(source, { debugName = "generated" })()
		end,
	})
	if not ok then
		failed += 1
		table.insert(failures, `{file}: load error: {specFn}`)
		return
	end
	local collected, err = pcall(specFn)
	if not collected then
		failed += 1
		table.insert(failures, `{file}: describe error: {err}`)
		return
	end
	for _, case in cases do
		local success, caseErr = pcall(case.fn)
		if success then
			passed += 1
		else
			failed += 1
			table.insert(failures, `{file}: {case.name}\n    {caseErr}`)
		end
	end
	print(`  {file}: {#cases} cases`)
end

local function collect(dir: string, out: { string })
	for _, entry in fs.readDir(dir) do
		local path = join(dir, entry)
		if fs.isDir(path) then
			collect(path, out)
		elseif string.match(entry, "%.spec%.luau$") then
			table.insert(out, path)
		end
	end
end

local specs: { string } = {}
for _, root in roots do
	local normalized = string.gsub(root, "\\", "/")
	normalized = string.gsub(normalized, "/$", "")
	collect(normalized, specs)
end
table.sort(specs)

print(`running {#specs} spec files`)
for _, file in specs do
	local instancePath = string.gsub(file, "%.luau$", "")
	runSpec(file, node(instancePath))
end

for _, failure in failures do
	print("FAIL " .. failure)
end
print(`{passed} passed, {failed} failed ({#warnings} SDK warnings captured)`)
process.exit(if failed > 0 then 1 else 0)

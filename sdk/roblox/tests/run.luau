-- Lune test runner for the SDK specs (no Roblox engine needed).
--
--   cd sdk/roblox
--   lune run tests/run.luau              -- every suite (core, purchases, analytics, tags)
--   lune run tests/run.luau core tags    -- only these folders
--
-- Builds a virtual instance tree (ReplicatedStorage.RoMetrics = src/, ReplicatedStorage.Tests = tests/),
-- loads each ModuleScript with `script` bound to its node, shims the few engine globals the specs
-- touch (Enum, typeof, task, DateTime, game:GetService) and runs TestEZ-style specs
-- (describe/it/beforeEach/afterEach + expect().to.equal/ok/throw, .never).
-- Specs inject their own fakes for Players/MarketplaceService/CollectionService etc.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")

local ROOT = process.env.ROMETRICS_SDK_ROOT or "."
if not fs.isDir(ROOT .. "/src") or not fs.isDir(ROOT .. "/tests") then
	print("run from sdk/roblox (or set ROMETRICS_SDK_ROOT)")
	process.exit(2)
end

local ALL_SUITES = { "core", "purchases", "analytics", "tags" }
local suites = if #process.args > 0 then process.args else ALL_SUITES

-- Enum shim: Enum.X.Y returns a stable fake EnumItem.
local enumItemMeta = {
	__tostring = function(self)
		return "Enum." .. self.EnumType .. "." .. self.Name
	end,
}
local Enum = setmetatable({}, {
	__index = function(self, typeName)
		local items = setmetatable({}, {
			__index = function(s, n)
				local it = setmetatable({ Name = n, EnumType = typeName, __enumitem = true }, enumItemMeta)
				rawset(s, n, it)
				return it
			end,
		})
		rawset(self, typeName, items)
		return items
	end,
})
local function fakeTypeof(v)
	if type(v) == "table" and rawget(v, "__enumitem") then
		return "EnumItem"
	end
	return type(v)
end

-- Minimal signal for engine services the SDK connects to at start.
local function signal()
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
	}
end

local guidN = 0
local services = {
	HttpService = {
		JSONEncode = function(_, v)
			return serde.encode("json", v)
		end,
		JSONDecode = function(_, s)
			return serde.decode("json", s)
		end,
		GenerateGUID = function()
			guidN += 1
			return string.format("{0000ABCD-0000-4000-8000-%012d}", guidN)
		end,
	},
	Players = {
		GetPlayers = function()
			return {}
		end,
		MaxPlayers = 0,
		PlayerAdded = signal(),
		PlayerRemoving = signal(),
	},
	LocalizationService = {},
	RunService = {
		IsStudio = function()
			return false
		end,
		IsServer = function()
			return true
		end,
	},
}
local game = {
	JobId = "",
	GameId = 0,
	PlaceId = 0,
	PlaceVersion = 0,
	PrivateServerId = "",
	PrivateServerOwnerId = 0,
	GetService = function(_, name)
		local s = services[name]
		if not s then
			error("service not faked: " .. name)
		end
		return s
	end,
	BindToClose = function() end,
}
local DateTime = {
	now = function()
		return { UnixTimestampMillis = math.floor(os.clock() * 1000) + 1700000000000 }
	end,
}

-- Synchronous task shim: spawn runs immediately, waits return instantly.
local taskLib = {
	spawn = function(fn, ...)
		local co = coroutine.create(fn)
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			error(err)
		end
		return co
	end,
	wait = function(n)
		return n or 0
	end,
	delay = function() end,
	defer = function(fn, ...)
		fn(...)
	end,
}

-- Virtual instance tree --------------------------------------------------------
local nodeMeta = {}
nodeMeta.__index = function(self, k)
	local m = rawget(nodeMeta, k)
	if m then
		return m
	end
	local child = rawget(self, "_children")[k]
	if child then
		return child
	end
	error("child not found: " .. tostring(k) .. " in " .. rawget(self, "Name"))
end
function nodeMeta.FindFirstChild(self, n)
	return rawget(self, "_children")[n]
end
function nodeMeta.IsA(self, c)
	return c == rawget(self, "ClassName")
end
function nodeMeta.GetFullName(self)
	local p = rawget(self, "Parent")
	return (p and p:GetFullName() .. "." or "") .. rawget(self, "Name")
end

local function newNode(name, className, parent, path)
	local n = setmetatable(
		{ Name = name, ClassName = className, Parent = parent, _children = {}, _path = path },
		nodeMeta
	)
	if parent then
		rawget(parent, "_children")[name] = n
	end
	return n
end

local function build(dir, node)
	for _, entry in fs.readDir(dir) do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			local initPath = full .. "/init.luau"
			local hasInit = fs.isFile(initPath)
			local child = newNode(entry, if hasInit then "ModuleScript" else "Folder", node, if hasInit then initPath else nil)
			build(full, child)
		elseif entry ~= "init.luau" and string.match(entry, "%.luau$") then
			local base = string.gsub(entry, "%.luau$", "")
			local class = "ModuleScript"
			if string.match(base, "%.client$") then
				class = "LocalScript"
				base = string.gsub(base, "%.client$", "")
			elseif string.match(base, "%.server$") then
				class = "Script"
				base = string.gsub(base, "%.server$", "")
			end
			newNode(base, class, node, full)
		end
	end
end

local dataModel = newNode("game", "DataModel", nil, nil)
local rs = newNode("ReplicatedStorage", "Folder", dataModel, nil)
services.ReplicatedStorage = rs
local lib = newNode("RoMetrics", "ModuleScript", rs, ROOT .. "/src/init.luau")
build(ROOT .. "/src", lib)
local tests = newNode("Tests", "Folder", rs, nil)
build(ROOT .. "/tests", tests)

local cache = {}
local env
local function req(node)
	if cache[node] ~= nil then
		return cache[node]
	end
	local path = rawget(node, "_path")
	assert(path, "cannot require " .. rawget(node, "Name"))
	local fenv = setmetatable({ script = node }, { __index = env })
	local fn = luau.load(fs.readFile(path), { debugName = node:GetFullName(), environment = fenv, injectGlobals = false })
	local result = fn()
	cache[node] = result
	return result
end

-- TestEZ-like DSL ----------------------------------------------------------------
local failures, passes = 0, 0
local stack = {}
local hooks = { before = {}, after = {} }

local function makeExpect(actual)
	local negate = false
	local e = {}
	local function check(cond, msg)
		if negate then
			cond = not cond
			msg = "not " .. msg
		end
		if not cond then
			error(msg, 3)
		end
	end
	e.to = e
	e.be = e
	e.never = setmetatable({}, {
		__index = function(_, k)
			negate = true
			return e[k]
		end,
	})
	e.equal = function(expected)
		check(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
	end
	e.ok = function()
		check(actual ~= nil and actual ~= false, "expected ok")
	end
	e.throw = function()
		check(not pcall(actual), "expected throw")
	end
	return e
end

env = setmetatable({
	game = game,
	Enum = Enum,
	typeof = fakeTypeof,
	task = taskLib,
	DateTime = DateTime,
	require = req,
	warn = function() end,
	print = print,
	workspace = {},
	expect = makeExpect,
	describe = function(name, fn)
		table.insert(stack, name)
		local saved = { before = table.clone(hooks.before), after = table.clone(hooks.after) }
		fn()
		hooks.before, hooks.after = saved.before, saved.after
		table.remove(stack)
	end,
	it = function(name, fn)
		for _, h in hooks.before do
			h()
		end
		local ok, err = pcall(fn)
		for _, h in hooks.after do
			h()
		end
		local label = table.concat(stack, " > ") .. " > " .. name
		if ok then
			passes += 1
		else
			failures += 1
			print("FAIL " .. label .. "\n    " .. tostring(err))
		end
	end,
	beforeEach = function(fn)
		table.insert(hooks.before, fn)
	end,
	afterEach = function(fn)
		table.insert(hooks.after, fn)
	end,
	-- Builtins are not reachable through _G with injectGlobals = false.
	string = string,
	table = table,
	math = math,
	type = type,
	tostring = tostring,
	tonumber = tonumber,
	pairs = pairs,
	ipairs = ipairs,
	next = next,
	pcall = pcall,
	xpcall = xpcall,
	error = error,
	select = select,
	setmetatable = setmetatable,
	getmetatable = getmetatable,
	rawget = rawget,
	rawset = rawset,
	rawequal = rawequal,
	coroutine = coroutine,
	os = os,
	assert = assert,
	utf8 = utf8,
	bit32 = bit32,
	buffer = buffer,
	unpack = table.unpack,
}, { __index = _G })

local function runSpecs(node)
	local names = {}
	for name in rawget(node, "_children") do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local child = rawget(node, "_children")[name]
		if string.match(name, "%.spec$") then
			print("== " .. child:GetFullName())
			local ok, err = pcall(function()
				req(child)()
			end)
			if not ok then
				failures += 1
				print("FAIL (load) " .. child:GetFullName() .. "\n    " .. tostring(err))
			end
		else
			runSpecs(child)
		end
	end
end

for _, folder in suites do
	local n = rawget(tests, "_children")[folder]
	if n then
		runSpecs(n)
	else
		failures += 1
		print("unknown suite: " .. folder)
	end
end
print(string.format("passed %d, failed %d", passes, failures))
if failures > 0 then
	process.exit(1)
end

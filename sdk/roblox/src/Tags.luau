--!strict
-- Owned by the Studio plugin agent (#11). Tag/attribute-driven auto events (CollectionService):
-- instances tagged `RoMetrics` by the Studio plugin emit custom events without code.
--
--   RM_Event      string   event name (required)
--   RM_Trigger    string   Touched | ProximityPrompt | ClickDetector | Activated (inferred when absent)
--   RM_Value      number   event value
--   RM_Cooldown   number   seconds between fires, per player, per instance (Touched: at least 1 s)
--   RM_Once       boolean  fire once per player session, per instance
--   RM_Prop_<key> any      extra props
--
-- Also loads the event registry the plugin maintains (ReplicatedStorage.RoMetricsEvents), only to
-- warn (debug) about unregistered names. Nothing here may throw into game code.
local Types = require(script.Parent.Types)
local Log = require(script.Parent.Util.Log)

local Tags = {}

Tags.TAG = "RoMetrics"
Tags.REGISTRY_NAME = "RoMetricsEvents"
Tags.TRIGGERS = { "Touched", "ProximityPrompt", "ClickDetector", "Activated" }
Tags.TOUCH_MIN_COOLDOWN = 1
local PROP_PREFIX = "RM_Prop_"
local MAX_NAME = 64

export type Trigger = "Touched" | "ProximityPrompt" | "ClickDetector" | "Activated"

export type Spec = {
	event: string,
	trigger: Trigger,
	value: number?,
	cooldown: number,
	once: boolean,
	props: { [string]: any },
}

export type LogFn = (player: Player?, name: string, value: number?, props: { [string]: any }?) -> ()

-- Everything the controller touches in the engine, injectable for tests.
export type Deps = {
	collection: any, -- CollectionService-like: GetTagged, GetInstanceAddedSignal, GetInstanceRemovedSignal
	players: any, -- Players-like: GetPlayerFromCharacter, PlayerRemoving
	now: () -> number,
	registry: { [string]: boolean }?, -- lower-cased registered names; nil = no registry
}

type Connection = { Disconnect: (self: any) -> () }

type Binding = {
	instance: Instance,
	spec: Spec?,
	connections: { Connection },
	lastFired: { [number]: number },
	onceFired: { [number]: string },
}

export type Controller = {
	bind: (self: Controller, instance: Instance) -> (),
	unbind: (self: Controller, instance: Instance) -> (),
	isBound: (self: Controller, instance: Instance) -> boolean,
	count: (self: Controller) -> number,
	destroy: (self: Controller) -> (),
}

local VALID_TRIGGER: { [string]: Trigger } = {
	Touched = "Touched",
	ProximityPrompt = "ProximityPrompt",
	ClickDetector = "ClickDetector",
	Activated = "Activated",
}

function Tags.isValidName(name: unknown): boolean
	if type(name) ~= "string" then
		return false
	end
	return #name >= 1 and #name <= MAX_NAME and string.match(name, "^[%w_%.:%-]+$") ~= nil
end

-- Trigger implied by the instance class when RM_Trigger is absent.
function Tags.inferTrigger(instance: any): Trigger?
	if instance:IsA("ProximityPrompt") then
		return "ProximityPrompt"
	elseif instance:IsA("ClickDetector") then
		return "ClickDetector"
	elseif instance:IsA("Tool") then
		return "Activated"
	elseif instance:IsA("BasePart") or instance:IsA("Model") or instance:IsA("Folder") then
		return "Touched"
	end
	return nil
end

local function primitive(value: any): any
	local t = type(value)
	if t == "string" or t == "number" or t == "boolean" then
		return value
	end
	return tostring(value)
end

-- Reads the RM_* attributes. Returns (spec, nil) or (nil, reason).
function Tags.readSpec(instance: any): (Spec?, string?)
	local attributes = instance:GetAttributes()
	local event = attributes.RM_Event
	if not Tags.isValidName(event) then
		return nil, `invalid or missing RM_Event ({tostring(event)})`
	end
	local trigger: Trigger?
	local rawTrigger = attributes.RM_Trigger
	if rawTrigger == nil or rawTrigger == "" then
		trigger = Tags.inferTrigger(instance)
		if not trigger then
			return nil, `cannot infer RM_Trigger for a {instance.ClassName}`
		end
	else
		trigger = VALID_TRIGGER[tostring(rawTrigger)]
		if not trigger then
			return nil, `unsupported RM_Trigger '{tostring(rawTrigger)}'`
		end
	end
	local value = attributes.RM_Value
	if value ~= nil and (type(value) ~= "number" or value ~= value) then
		value = tonumber(value)
	end
	local cooldown = tonumber(attributes.RM_Cooldown) or 0
	if cooldown ~= cooldown or cooldown < 0 then
		cooldown = 0
	end
	local props: { [string]: any } = {}
	for key, raw in attributes do
		if string.sub(key, 1, #PROP_PREFIX) == PROP_PREFIX and #key > #PROP_PREFIX then
			props[string.sub(key, #PROP_PREFIX + 1)] = primitive(raw)
		end
	end
	return {
		event = event :: string,
		trigger = trigger :: Trigger,
		value = value,
		cooldown = cooldown,
		once = attributes.RM_Once == true,
		props = props,
	},
		nil
end

-- Walks up from a touching part to the character model owned by a player.
function Tags.resolvePlayer(players: any, hit: any): Player?
	local node = hit
	while node do
		if node:IsA("Model") then
			local player = players:GetPlayerFromCharacter(node)
			if player then
				return player
			end
		end
		node = node.Parent
	end
	return nil
end

-- Returns lower-cased names from a registry ModuleScript's value, or nil when unreadable.
function Tags.registryNames(value: unknown): { [string]: boolean }?
	if type(value) ~= "table" then
		return nil
	end
	local events = (value :: any).events
	if type(events) ~= "table" then
		return nil
	end
	local names: { [string]: boolean } = {}
	for _, def in events do
		if type(def) == "table" and type(def.name) == "string" then
			names[string.lower(def.name)] = true
		end
	end
	return names
end

local function safeCall(label: string, fn: (...any) -> (), ...: any)
	local ok, err = pcall(fn :: any, ...)
	if not ok then
		Log.warn(`Tags {label} failed: {err}`)
	end
end

function Tags.new(sessions: Types.SessionTracker, log: LogFn, deps: Deps): Controller
	local bindings: { [Instance]: Binding } = {}
	local globalConnections: { Connection } = {}
	local self = {} :: Controller

	local function fire(binding: Binding, player: Player?)
		local spec = binding.spec
		if not spec or not player then
			return
		end
		local userId = (player :: any).UserId :: number
		local sessionKey = tostring(userId)
		if spec.once then
			local session = sessions:get(player)
			if session then
				sessionKey = session.sessionId
			end
			if binding.onceFired[userId] == sessionKey then
				return
			end
		end
		local cooldown = spec.cooldown
		if spec.trigger == "Touched" then
			cooldown = math.max(cooldown, Tags.TOUCH_MIN_COOLDOWN)
		end
		local now = deps.now()
		local last = binding.lastFired[userId]
		if cooldown > 0 and last and now - last < cooldown then
			return
		end
		binding.lastFired[userId] = now
		if spec.once then
			binding.onceFired[userId] = sessionKey
		end
		local props = table.clone(spec.props)
		if props.trigger == nil then
			props.trigger = spec.trigger
		end
		if props.instance == nil then
			props.instance = (binding.instance :: any).Name
		end
		safeCall("log", log, player, spec.event, spec.value, props)
	end

	local function connect(binding: Binding, signal: any, handler: (...any) -> ())
		table.insert(
			binding.connections,
			signal:Connect(function(...)
				safeCall("handler", handler, ...)
			end)
		)
	end

	-- Binds `handler(target)` to the instance itself or its first descendant of `className`,
	-- waiting for one to appear when missing.
	local function withTarget(binding: Binding, className: string, handler: (target: any) -> ())
		local instance: any = binding.instance
		if instance:IsA(className) then
			handler(instance)
			return
		end
		local found = instance:FindFirstChildWhichIsA(className, true)
		if found then
			handler(found)
			return
		end
		local bound = false
		connect(binding, instance.DescendantAdded, function(descendant: any)
			if not bound and descendant:IsA(className) then
				bound = true
				handler(descendant)
			end
		end)
	end

	local function attachTrigger(binding: Binding, spec: Spec)
		local instance: any = binding.instance
		if spec.trigger == "Touched" then
			local function bindPart(part: any)
				connect(binding, part.Touched, function(hit: any)
					fire(binding, Tags.resolvePlayer(deps.players, hit))
				end)
			end
			if instance:IsA("BasePart") then
				bindPart(instance)
			else
				for _, descendant in instance:GetDescendants() do
					if descendant:IsA("BasePart") then
						bindPart(descendant)
					end
				end
				connect(binding, instance.DescendantAdded, function(descendant: any)
					if descendant:IsA("BasePart") then
						bindPart(descendant)
					end
				end)
			end
		elseif spec.trigger == "ProximityPrompt" then
			withTarget(binding, "ProximityPrompt", function(prompt: any)
				connect(binding, prompt.Triggered, function(player: Player)
					fire(binding, player)
				end)
			end)
		elseif spec.trigger == "ClickDetector" then
			withTarget(binding, "ClickDetector", function(detector: any)
				connect(binding, detector.MouseClick, function(player: Player)
					fire(binding, player)
				end)
			end)
		elseif spec.trigger == "Activated" then
			if not instance:IsA("Tool") then
				Log.warn(`Tags: RM_Trigger 'Activated' needs a Tool ({instance:GetFullName()})`)
				return
			end
			connect(binding, instance.Activated, function()
				fire(binding, deps.players:GetPlayerFromCharacter(instance.Parent))
			end)
		end
	end

	local function disconnectAll(binding: Binding)
		for _, connection in binding.connections do
			pcall(function()
				connection:Disconnect()
			end)
		end
		table.clear(binding.connections)
	end

	function self.bind(_: Controller, instance: Instance)
		if bindings[instance] then
			self:unbind(instance)
		end
		local binding: Binding = {
			instance = instance,
			spec = nil,
			connections = {},
			lastFired = {},
			onceFired = {},
		}
		bindings[instance] = binding
		local inst: any = instance
		-- Rebind when the plugin (or a script) edits RM_* attributes at runtime.
		connect(binding, inst.AttributeChanged, function(attribute: string)
			if string.sub(attribute, 1, 3) == "RM_" and bindings[instance] == binding then
				self:bind(instance)
			end
		end)
		local spec, reason = Tags.readSpec(inst)
		if not spec then
			Log.warn(`Tags: ignoring {inst:GetFullName()}: {reason}`)
			return
		end
		binding.spec = spec
		if deps.registry and not deps.registry[string.lower(spec.event)] then
			Log.debug(`Tags: event '{spec.event}' is not in {Tags.REGISTRY_NAME} ({inst:GetFullName()})`)
		end
		attachTrigger(binding, spec)
	end

	function self.unbind(_: Controller, instance: Instance)
		local binding = bindings[instance]
		if binding then
			bindings[instance] = nil
			disconnectAll(binding)
		end
	end

	function self.isBound(_: Controller, instance: Instance): boolean
		local binding = bindings[instance]
		return binding ~= nil and binding.spec ~= nil
	end

	function self.count(_: Controller): number
		local n = 0
		for _, binding in bindings do
			if binding.spec then
				n += 1
			end
		end
		return n
	end

	function self.destroy(_: Controller)
		for _, connection in globalConnections do
			pcall(function()
				connection:Disconnect()
			end)
		end
		table.clear(globalConnections)
		for instance in bindings do
			self:unbind(instance)
		end
	end

	local collection = deps.collection
	table.insert(
		globalConnections,
		collection:GetInstanceAddedSignal(Tags.TAG):Connect(function(instance: Instance)
			safeCall("bind", function()
				self:bind(instance)
			end)
		end)
	)
	table.insert(
		globalConnections,
		collection:GetInstanceRemovedSignal(Tags.TAG):Connect(function(instance: Instance)
			safeCall("unbind", function()
				self:unbind(instance)
			end)
		end)
	)
	if deps.players.PlayerRemoving then
		table.insert(
			globalConnections,
			deps.players.PlayerRemoving:Connect(function(player: any)
				local userId = player.UserId
				for _, binding in bindings do
					binding.lastFired[userId] = nil
					binding.onceFired[userId] = nil
				end
			end)
		)
	end
	for _, instance in collection:GetTagged(Tags.TAG) do
		safeCall("bind", function()
			self:bind(instance)
		end)
	end
	return self
end

local function loadRegistry(): { [string]: boolean }?
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local module = ReplicatedStorage:FindFirstChild(Tags.REGISTRY_NAME)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, value = pcall(require, module)
	if not ok then
		Log.warn(`could not load {Tags.REGISTRY_NAME}: {value}`)
		return nil
	end
	return Tags.registryNames(value)
end

-- `log(player?, name, value?, props?)` emits a custom event through Analytics.
function Tags.start(config: Types.Config, sessions: Types.SessionTracker, log: LogFn): Controller?
	local _ = config
	local ok, result = pcall(function()
		return Tags.new(sessions, log, {
			collection = game:GetService("CollectionService"),
			players = game:GetService("Players"),
			now = os.clock,
			registry = loadRegistry(),
		})
	end)
	if not ok then
		Log.warn(`Tags failed to start: {result}`)
		return nil
	end
	return result
end

return Tags

--!strict
-- Test doubles for Tags: minimal Instance/Signal/CollectionService/Players fakes (no engine needed).

local Fakes = {}

local SUPERCLASSES: { [string]: { string } } = {
	Part = { "BasePart" },
	MeshPart = { "BasePart" },
}

export type Signal = {
	handlers: { (...any) -> () },
	Connect: (self: Signal, handler: (...any) -> ()) -> { Disconnect: (self: any) -> () },
	Fire: (self: Signal, ...any) -> (),
	count: (self: Signal) -> number,
}

function Fakes.signal(): Signal
	local signal = { handlers = {} } :: any
	function signal.Connect(self: any, handler: (...any) -> ())
		local entry = { fn = handler }
		table.insert(self.handlers, entry)
		return {
			Disconnect = function()
				local index = table.find(self.handlers, entry)
				if index then
					table.remove(self.handlers, index)
				end
			end,
		}
	end
	function signal.Fire(self: any, ...: any)
		for _, entry: any in table.clone(self.handlers) do
			entry.fn(...)
		end
	end
	function signal.count(self: any): number
		return #self.handlers
	end
	return signal :: Signal
end

function Fakes.instance(className: string, name: string?, parent: any?): any
	local inst = {
		ClassName = className,
		Name = name or className,
		Parent = nil,
		children = {},
		attributes = {},
		AttributeChanged = Fakes.signal(),
		DescendantAdded = Fakes.signal(),
		Touched = Fakes.signal(),
		Triggered = Fakes.signal(),
		MouseClick = Fakes.signal(),
		Activated = Fakes.signal(),
	} :: any
	function inst.IsA(self: any, class: string): boolean
		if self.ClassName == class or class == "Instance" then
			return true
		end
		local supers = SUPERCLASSES[self.ClassName]
		return supers ~= nil and table.find(supers, class) ~= nil
	end
	function inst.GetAttributes(self: any)
		return table.clone(self.attributes)
	end
	function inst.GetAttribute(self: any, key: string)
		return self.attributes[key]
	end
	function inst.SetAttribute(self: any, key: string, value: any)
		self.attributes[key] = value
		self.AttributeChanged:Fire(key)
	end
	function inst.GetFullName(self: any): string
		if self.Parent then
			return self.Parent:GetFullName() .. "." .. self.Name
		end
		return self.Name
	end
	function inst.GetDescendants(self: any)
		local out = {}
		local function walk(node: any)
			for _, child in node.children do
				table.insert(out, child)
				walk(child)
			end
		end
		walk(self)
		return out
	end
	function inst.FindFirstChildWhichIsA(self: any, class: string, recursive: boolean?)
		local list = if recursive then self:GetDescendants() else self.children
		for _, child in list do
			if child:IsA(class) then
				return child
			end
		end
		return nil
	end
	function inst.setParent(self: any, newParent: any)
		self.Parent = newParent
		table.insert(newParent.children, self)
		local node = newParent
		while node do
			node.DescendantAdded:Fire(self)
			node = node.Parent
		end
	end
	if parent then
		inst:setParent(parent)
	end
	return inst
end

function Fakes.collection()
	local collection = {
		tagged = {},
		added = Fakes.signal(),
		removed = Fakes.signal(),
	} :: any
	function collection.GetTagged(self: any, _tag: string)
		return table.clone(self.tagged)
	end
	function collection.GetInstanceAddedSignal(self: any, _tag: string)
		return self.added
	end
	function collection.GetInstanceRemovedSignal(self: any, _tag: string)
		return self.removed
	end
	function collection.AddTag(self: any, inst: any)
		table.insert(self.tagged, inst)
		self.added:Fire(inst)
	end
	function collection.RemoveTag(self: any, inst: any)
		local index = table.find(self.tagged, inst)
		if index then
			table.remove(self.tagged, index)
		end
		self.removed:Fire(inst)
	end
	return collection
end

-- A player plus its character model (with a HumanoidRootPart-like child part).
function Fakes.player(userId: number)
	local character = Fakes.instance("Model", `Character{userId}`)
	local limb = Fakes.instance("Part", "LeftFoot", character)
	return { UserId = userId, Name = `Player{userId}`, Character = character }, limb
end

function Fakes.players(list: { any })
	local players = { PlayerRemoving = Fakes.signal() } :: any
	function players.GetPlayerFromCharacter(_self: any, character: any)
		for _, player in list do
			if player.Character == character then
				return player
			end
		end
		return nil
	end
	return players
end

function Fakes.sessions()
	local sessions = { byUser = {} } :: any
	function sessions.get(self: any, player: any)
		return self.byUser[player.UserId]
	end
	function sessions.set(self: any, player: any, sessionId: string)
		self.byUser[player.UserId] = { sessionId = sessionId, userId = player.UserId, startedAt = 0 }
	end
	function sessions.destroy() end
	return sessions
end

function Fakes.clock()
	local clock = { t = 100 } :: any
	clock.now = function(): number
		return clock.t
	end
	return clock
end

-- Recording log function: calls[i] = { player, name, value, props }.
function Fakes.recorder()
	local recorder = { calls = {} } :: any
	recorder.log = function(player: any, name: string, value: number?, props: any)
		table.insert(recorder.calls, { player = player, name = name, value = value, props = props })
	end
	return recorder
end

return Fakes

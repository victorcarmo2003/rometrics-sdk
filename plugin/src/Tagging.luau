--!strict
-- Tag/attribute edits on instances (with undo), snapshots for lint/UI, and the optional
-- highlight of tracked instances. Attribute contract: see the plugin docs.
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local CoreGui = game:GetService("CoreGui")

local Lint = require(script.Parent.Lint)

local Tagging = {}

Tagging.TAG = "RoMetrics"
Tagging.PROP_PREFIX = "RM_Prop_"
local BASE_ATTRIBUTES = { "RM_Event", "RM_Trigger", "RM_Value", "RM_Cooldown", "RM_Once" }

export type Spec = {
	event: string,
	trigger: string?, -- nil/"Auto" = inferred by the SDK
	value: number?,
	cooldown: number?,
	once: boolean,
	props: { [string]: any },
}

-- Runs `fn` inside one undo step. Returns fn's error message, if any.
function Tagging.record(name: string, fn: () -> ()): string?
	local recording: string? = nil
	pcall(function()
		recording = ChangeHistoryService:TryBeginRecording(name)
	end)
	local ok, err = pcall(fn :: any)
	if recording then
		pcall(function()
			ChangeHistoryService:FinishRecording(
				recording :: string,
				if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
			)
		end)
	end
	return if ok then nil else tostring(err)
end

local function isInPlace(instance: Instance): boolean
	return instance:IsDescendantOf(game) and not instance:IsDescendantOf(CoreGui)
end

function Tagging.tagged(): { Instance }
	local out = {}
	for _, instance in CollectionService:GetTagged(Tagging.TAG) do
		if isInPlace(instance) then
			table.insert(out, instance)
		end
	end
	table.sort(out, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	return out
end

function Tagging.isTagged(instance: Instance): boolean
	return instance:HasTag(Tagging.TAG)
end

-- Reads the current spec of an instance (for prefilling the form).
function Tagging.read(instance: Instance): Spec?
	if not Tagging.isTagged(instance) then
		return nil
	end
	local attributes = instance:GetAttributes()
	local props = {}
	for key, value in attributes do
		if string.sub(key, 1, #Tagging.PROP_PREFIX) == Tagging.PROP_PREFIX then
			props[string.sub(key, #Tagging.PROP_PREFIX + 1)] = value
		end
	end
	local trigger = attributes.RM_Trigger
	return {
		event = if type(attributes.RM_Event) == "string" then attributes.RM_Event else "",
		trigger = if type(trigger) == "string" and trigger ~= "" then trigger else nil,
		value = if type(attributes.RM_Value) == "number" then attributes.RM_Value else nil,
		cooldown = if type(attributes.RM_Cooldown) == "number" then attributes.RM_Cooldown else nil,
		once = attributes.RM_Once == true,
		props = props,
	}
end

local function clearAttributes(instance: Instance)
	for _, key in BASE_ATTRIBUTES do
		instance:SetAttribute(key, nil)
	end
	for key in instance:GetAttributes() do
		if string.sub(key, 1, #Tagging.PROP_PREFIX) == Tagging.PROP_PREFIX then
			instance:SetAttribute(key, nil)
		end
	end
end

local function writeSpec(instance: Instance, spec: Spec)
	clearAttributes(instance)
	instance:AddTag(Tagging.TAG)
	instance:SetAttribute("RM_Event", spec.event)
	if spec.trigger and spec.trigger ~= "Auto" then
		instance:SetAttribute("RM_Trigger", spec.trigger)
	end
	if spec.value ~= nil then
		instance:SetAttribute("RM_Value", spec.value)
	end
	if spec.cooldown and spec.cooldown > 0 then
		instance:SetAttribute("RM_Cooldown", spec.cooldown)
	end
	if spec.once then
		instance:SetAttribute("RM_Once", true)
	end
	for key, value in spec.props do
		if key ~= "" then
			instance:SetAttribute(Tagging.PROP_PREFIX .. key, value)
		end
	end
end

function Tagging.apply(instances: { Instance }, spec: Spec): string?
	return Tagging.record(`RoMetrics: rastrear {spec.event}`, function()
		for _, instance in instances do
			writeSpec(instance, spec)
		end
	end)
end

function Tagging.remove(instances: { Instance }): string?
	return Tagging.record("RoMetrics: remover rastreio", function()
		for _, instance in instances do
			clearAttributes(instance)
			instance:RemoveTag(Tagging.TAG)
		end
	end)
end

function Tagging.withEvent(name: string): { Instance }
	local out = {}
	local lower = string.lower(name)
	for _, instance in Tagging.tagged() do
		local event = instance:GetAttribute("RM_Event")
		if type(event) == "string" and string.lower(event) == lower then
			table.insert(out, instance)
		end
	end
	return out
end

-- Rewrites RM_Event on every instance tagged with `from`. Call inside Tagging.record.
function Tagging.renameEvent(from: string, to: string): number
	local instances = Tagging.withEvent(from)
	for _, instance in instances do
		instance:SetAttribute("RM_Event", to)
	end
	return #instances
end

function Tagging.describe(instance: Instance): Lint.TaggedInfo
	local hasParts = false
	local hasPrompt = false
	local hasDetector = false
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			hasParts = true
		elseif descendant:IsA("ProximityPrompt") then
			hasPrompt = true
		elseif descendant:IsA("ClickDetector") then
			hasDetector = true
		end
	end
	return {
		ref = instance,
		path = instance:GetFullName(),
		className = instance.ClassName,
		attributes = instance:GetAttributes(),
		isPart = instance:IsA("BasePart"),
		isContainer = instance:IsA("Model") or instance:IsA("Folder"),
		hasParts = hasParts,
		hasPrompt = hasPrompt or instance:IsA("ProximityPrompt"),
		hasDetector = hasDetector or instance:IsA("ClickDetector"),
		isTool = instance:IsA("Tool"),
	}
end

-- Highlight ----------------------------------------------------------------------------------------

-- Part used to draw the selection box for an instance (prompts/detectors use their parent part).
local function adornee(instance: Instance): PVInstance?
	if instance:IsA("BasePart") or instance:IsA("Model") then
		return instance :: PVInstance
	end
	local parent = instance.Parent
	if parent and (parent:IsA("BasePart") or parent:IsA("Model")) then
		return parent :: PVInstance
	end
	return nil
end

export type Highlighter = {
	setEnabled: (self: Highlighter, enabled: boolean) -> (),
	refresh: (self: Highlighter) -> (),
	destroy: (self: Highlighter) -> (),
}

function Tagging.highlighter(color: Color3): Highlighter
	local folder: Folder? = nil
	local enabled = false
	local connections: { RBXScriptConnection } = {}
	local self = {} :: Highlighter

	function self.refresh(_: Highlighter)
		if folder then
			folder:ClearAllChildren()
		end
		if not enabled then
			return
		end
		if not folder then
			local created = Instance.new("Folder")
			created.Name = "RoMetricsHighlights"
			created.Archivable = false
			created.Parent = CoreGui
			folder = created
		end
		for _, instance in Tagging.tagged() do
			local target = adornee(instance)
			if target then
				local box = Instance.new("SelectionBox")
				box.Adornee = target
				box.Color3 = color
				box.LineThickness = 0.04
				box.SurfaceColor3 = color
				box.SurfaceTransparency = 0.85
				box.Archivable = false
				box.Parent = folder
			end
		end
	end

	function self.setEnabled(_: Highlighter, value: boolean)
		enabled = value
		self:refresh()
	end

	function self.destroy(_: Highlighter)
		for _, connection in connections do
			connection:Disconnect()
		end
		if folder then
			folder:Destroy()
			folder = nil
		end
	end

	table.insert(
		connections,
		CollectionService:GetInstanceAddedSignal(Tagging.TAG):Connect(function()
			if enabled then
				self:refresh()
			end
		end)
	)
	table.insert(
		connections,
		CollectionService:GetInstanceRemovedSignal(Tagging.TAG):Connect(function()
			if enabled then
				self:refresh()
			end
		end)
	)
	return self
end

return Tagging

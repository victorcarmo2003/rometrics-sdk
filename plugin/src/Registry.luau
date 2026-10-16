--!strict
-- Event registry: the `ReplicatedStorage.RoMetricsEvents` ModuleScript the plugin reads and writes.
-- Pure data helpers (normalize/serialize/edit) plus two IO functions that need the engine.
local Names = require(script.Parent.Names)

local Registry = {}

Registry.MODULE_NAME = "RoMetricsEvents"
Registry.VERSION = 1

export type Kind = "custom" | "funnel" | "progression" | "economy"
export type Trigger = "code" | "tag"
export type PropType = "string" | "number" | "boolean"
export type PropDef = { key: string, type: PropType }
export type StepDef = { name: string, event: string? }
export type EventDef = {
	name: string,
	description: string,
	kind: Kind,
	trigger: Trigger,
	props: { PropDef },
	steps: { StepDef },
}
export type Registry = { version: number, events: { EventDef } }

local function oneOf(value: unknown, options: { string }, default: string): any
	if type(value) == "string" and table.find(options, value) then
		return value
	end
	return default
end

function Registry.empty(): Registry
	return { version = Registry.VERSION, events = {} }
end

function Registry.newEvent(name: string, kind: Kind?): EventDef
	return {
		name = name,
		description = "",
		kind = kind or "custom",
		trigger = "code",
		props = {},
		steps = {},
	}
end

-- Accepts anything (hand-edited module, older versions) and returns a well-formed registry plus
-- human-readable notes about what was dropped or fixed.
function Registry.normalize(raw: unknown): (Registry, { string })
	local notes: { string } = {}
	local registry = Registry.empty()
	if type(raw) ~= "table" then
		table.insert(notes, "registro não é uma tabela; começando vazio")
		return registry, notes
	end
	local events = (raw :: any).events
	if type(events) ~= "table" then
		table.insert(notes, "campo 'events' ausente; começando vazio")
		return registry, notes
	end
	for index, def in events do
		if type(def) ~= "table" or type(def.name) ~= "string" then
			table.insert(notes, `evento #{index} ignorado: sem 'name'`)
			continue
		end
		local event = Registry.newEvent(def.name, oneOf(def.kind, Names.KINDS, "custom"))
		event.description = if type(def.description) == "string" then def.description else ""
		event.trigger = oneOf(def.trigger, Names.TRIGGERS, "code")
		if type(def.props) == "table" then
			for _, prop in def.props do
				if type(prop) == "table" and type(prop.key) == "string" then
					table.insert(event.props, {
						key = prop.key,
						type = oneOf(prop.type, Names.PROP_TYPES, "string"),
					})
				elseif type(prop) == "string" then
					table.insert(event.props, { key = prop, type = "string" :: PropType })
				end
			end
		end
		if type(def.steps) == "table" then
			for _, step in def.steps do
				if type(step) == "string" then
					table.insert(event.steps, { name = step })
				elseif type(step) == "table" and type(step.name) == "string" then
					table.insert(event.steps, {
						name = step.name,
						event = if type(step.event) == "string" and step.event ~= "" then step.event else nil,
					})
				end
			end
		end
		table.insert(registry.events, event)
	end
	return registry, notes
end

function Registry.find(registry: Registry, name: string): (EventDef?, number?)
	local lower = string.lower(name)
	for index, event in registry.events do
		if string.lower(event.name) == lower then
			return event, index
		end
	end
	return nil, nil
end

function Registry.byKind(registry: Registry, kind: Kind): { EventDef }
	local out = {}
	for _, event in registry.events do
		if event.kind == kind then
			table.insert(out, event)
		end
	end
	return out
end

function Registry.clone(registry: Registry): Registry
	local copy = Registry.empty()
	copy.version = registry.version
	for _, event in registry.events do
		local e = table.clone(event)
		e.props = {}
		for _, prop in event.props do
			table.insert(e.props, table.clone(prop))
		end
		e.steps = {}
		for _, step in event.steps do
			table.insert(e.steps, table.clone(step))
		end
		table.insert(copy.events, e)
	end
	return copy
end

-- Inserts or replaces (by `previousName`, else by `event.name`). Returns an error message when the
-- name is invalid or taken by another event.
function Registry.upsert(registry: Registry, event: EventDef, previousName: string?): string?
	local nameError = Names.eventNameError(event.name)
	if nameError then
		return nameError
	end
	local _, existingIndex = Registry.find(registry, previousName or event.name)
	local _, clashIndex = Registry.find(registry, event.name)
	if clashIndex and clashIndex ~= existingIndex then
		return `já existe um evento '{registry.events[clashIndex].name}'`
	end
	if existingIndex then
		registry.events[existingIndex] = event
	else
		table.insert(registry.events, event)
	end
	return nil
end

-- Inserts a new event; fails when the name is invalid or already used (case-insensitive).
function Registry.add(registry: Registry, event: EventDef): string?
	local existing = Registry.find(registry, event.name)
	if existing then
		return `já existe um evento '{existing.name}'`
	end
	return Registry.upsert(registry, event)
end

function Registry.remove(registry: Registry, name: string): boolean
	local _, index = Registry.find(registry, name)
	if index then
		table.remove(registry.events, index)
		-- Funnel steps that pointed at the removed event lose the link.
		for _, event in registry.events do
			for _, step in event.steps do
				if step.event and string.lower(step.event) == string.lower(name) then
					step.event = nil
				end
			end
		end
		return true
	end
	return false
end

-- Renames an event and every funnel-step reference to it.
function Registry.rename(registry: Registry, from: string, to: string): string?
	local event = Registry.find(registry, from)
	if not event then
		return `evento '{from}' não existe`
	end
	local renamed = table.clone(event)
	renamed.name = to
	local err = Registry.upsert(registry, renamed, from)
	if err then
		return err
	end
	for _, other in registry.events do
		for _, step in other.steps do
			if step.event and string.lower(step.event) == string.lower(from) then
				step.event = to
			end
		end
	end
	return nil
end

-- Serialization -----------------------------------------------------------------------------------

local function quote(value: string): string
	local escaped = string.gsub(value, '[%c"\\]', function(c: string): string
		if c == "\n" then
			return "\\n"
		elseif c == "\t" then
			return "\\t"
		elseif c == "\r" then
			return "\\r"
		elseif c == '"' or c == "\\" then
			return "\\" .. c
		end
		return string.format("\\%03d", string.byte(c))
	end)
	return `"{escaped}"`
end
Registry.quote = quote

function Registry.serialize(registry: Registry): string
	local lines = {
		"--!strict",
		"-- RoMetrics event registry. Generated by the RoMetrics Studio plugin; hand edits are kept",
		"-- as long as the shape stays the same. Read by the plugin and by the SDK (Tags).",
		"return {",
		`\tversion = {Registry.VERSION},`,
		"\tevents = {",
	}
	for _, event in registry.events do
		table.insert(lines, "\t\t{")
		table.insert(lines, `\t\t\tname = {quote(event.name)},`)
		if event.description ~= "" then
			table.insert(lines, `\t\t\tdescription = {quote(event.description)},`)
		end
		table.insert(lines, `\t\t\tkind = {quote(event.kind)},`)
		table.insert(lines, `\t\t\ttrigger = {quote(event.trigger)},`)
		if #event.props > 0 then
			table.insert(lines, "\t\t\tprops = {")
			for _, prop in event.props do
				table.insert(lines, `\t\t\t\t\{ key = {quote(prop.key)}, type = {quote(prop.type)} },`)
			end
			table.insert(lines, "\t\t\t},")
		end
		if #event.steps > 0 then
			table.insert(lines, "\t\t\tsteps = {")
			for _, step in event.steps do
				if step.event then
					table.insert(lines, `\t\t\t\t\{ name = {quote(step.name)}, event = {quote(step.event)} },`)
				else
					table.insert(lines, `\t\t\t\t\{ name = {quote(step.name)} },`)
				end
			end
			table.insert(lines, "\t\t\t},")
		end
		table.insert(lines, "\t\t},")
	end
	table.insert(lines, "\t},")
	table.insert(lines, "}")
	return table.concat(lines, "\n") .. "\n"
end

-- Engine IO ---------------------------------------------------------------------------------------

-- Reads a registry ModuleScript. `require` caches by instance, so a fresh clone is required each time.
function Registry.read(module: ModuleScript): (Registry, { string })
	local clone = module:Clone()
	local ok, value = pcall(require, clone)
	clone:Destroy()
	if not ok then
		local registry = Registry.empty()
		return registry, { `erro ao carregar {module:GetFullName()}: {value}` }
	end
	return Registry.normalize(value)
end

return Registry

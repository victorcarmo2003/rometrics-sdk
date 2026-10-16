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

-- Safe data parser ----------------------------------------------------------------------------------
-- The registry lives in the place, which may come from an untrusted source (downloaded place or
-- model). It must NEVER be `require`d from the plugin (that would run its code with plugin
-- permissions). This parses only the literal subset `serialize` emits:
--   `return { key = "str" | number | true | false | nil | { ... }, ... }` plus comments.

local MAX_DEPTH = 8
local MAX_SOURCE = 1_000_000

local ESCAPES: { [string]: string } = { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["\\"] = "\\", ["'"] = "'" }

-- Returns (value, nil) or (nil, reason). Pure; unit tested.
function Registry.parse(source: string): (unknown, string?)
	if #source > MAX_SOURCE then
		return nil, "source muito grande"
	end
	local pos = 1
	local len = #source

	local function skip()
		while pos <= len do
			local c = string.sub(source, pos, pos)
			if string.find(c, "^%s$") then
				pos += 1
			elseif string.sub(source, pos, pos + 1) == "--" then
				local nl = string.find(source, "\n", pos, true)
				pos = if nl then nl + 1 else len + 1
			else
				break
			end
		end
	end

	local parseValue: (depth: number) -> unknown

	local function parseString(): string
		local quoteChar = string.sub(source, pos, pos)
		pos += 1
		local out = {}
		while true do
			if pos > len then
				error("string não terminada", 0)
			end
			local c = string.sub(source, pos, pos)
			if c == quoteChar then
				pos += 1
				return table.concat(out)
			elseif c == "\\" then
				local nextChar = string.sub(source, pos + 1, pos + 1)
				local digits = string.match(source, "^%d%d?%d?", pos + 1)
				if digits then
					local code = tonumber(digits) :: number
					if code > 255 then
						error("escape inválido", 0)
					end
					table.insert(out, string.char(code))
					pos += 1 + #digits
				elseif ESCAPES[nextChar] then
					table.insert(out, ESCAPES[nextChar] :: string)
					pos += 2
				else
					error("escape não suportado", 0)
				end
			elseif c == "\n" then
				error("string com quebra de linha", 0)
			else
				table.insert(out, c)
				pos += 1
			end
		end
	end

	local function parseTable(depth: number): { [unknown]: unknown }
		if depth > MAX_DEPTH then
			error("aninhamento excessivo", 0)
		end
		pos += 1 -- {
		local out: { [unknown]: unknown } = {}
		local arrayIndex = 1
		while true do
			skip()
			local c = string.sub(source, pos, pos)
			if c == "" then
				error("tabela não terminada", 0)
			elseif c == "}" then
				pos += 1
				return out
			end
			local ident = string.match(source, "^[%a_][%w_]*", pos)
			local afterIdent = if ident then pos + #ident else pos
			local key: unknown = nil
			if ident then
				local save = pos
				pos = afterIdent
				skip()
				if string.sub(source, pos, pos) == "=" and string.sub(source, pos + 1, pos + 1) ~= "=" then
					pos += 1
					key = ident
				else
					pos = save
				end
			end
			local value = parseValue(depth + 1)
			if key == nil then
				key = arrayIndex
				arrayIndex += 1
			end
			out[key] = value
			skip()
			local sep = string.sub(source, pos, pos)
			if sep == "," or sep == ";" then
				pos += 1
			elseif sep ~= "}" then
				error("esperado ',' ou '}'", 0)
			end
		end
	end

	parseValue = function(depth: number): unknown
		skip()
		local c = string.sub(source, pos, pos)
		if c == "{" then
			return parseTable(depth)
		elseif c == '"' or c == "'" then
			return parseString()
		end
		local number = string.match(source, "^%-?%d+%.?%d*", pos)
		if number then
			pos += #number
			return tonumber(number)
		end
		local word = string.match(source, "^[%a_][%w_]*", pos)
		if word == "true" or word == "false" or word == "nil" then
			pos += #word
			return if word == "true" then true elseif word == "false" then false else nil
		end
		error(`expressão não suportada na posição {pos}`, 0)
	end

	local ok, result = pcall(function()
		skip()
		if string.sub(source, pos, pos + 5) ~= "return" then
			error("esperado 'return'", 0)
		end
		pos += 6
		local value = parseValue(1)
		skip()
		if pos <= len then
			error("conteúdo inesperado após o retorno", 0)
		end
		return value
	end)
	if not ok then
		return nil, tostring(result)
	end
	return result, nil
end

-- Reads a registry ModuleScript WITHOUT executing it (see Registry.parse).
function Registry.read(module: ModuleScript): (Registry, { string })
	local okSource, source = pcall(function()
		return game:GetService("ScriptEditorService"):GetEditorSource(module)
	end)
	if not okSource or type(source) ~= "string" then
		local okRaw, raw = pcall(function()
			return (module :: any).Source
		end)
		source = if okRaw and type(raw) == "string" then raw else nil
	end
	if type(source) ~= "string" then
		return Registry.empty(), { `não foi possível ler {module:GetFullName()}` }
	end
	local value, err = Registry.parse(source)
	if err then
		return Registry.empty(), { `erro ao ler {module:GetFullName()}: {err} (o módulo não é executado pelo plugin)` }
	end
	return Registry.normalize(value)
end

return Registry

--!strict
-- Naming rules shared by the registry, tagging and lint. Mirrors the ingest
-- server rule for event names: /^[A-Za-z0-9_.:-]{1,64}$/.

local Names = {}

Names.MAX_NAME = 64
Names.KINDS = { "custom", "funnel", "progression", "economy" }
Names.TRIGGERS = { "code", "tag" }
Names.PROP_TYPES = { "string", "number", "boolean" }
Names.TAG_TRIGGERS = { "Auto", "Touched", "ProximityPrompt", "ClickDetector", "Activated" }

function Names.isValidEventName(name: unknown): boolean
	if type(name) ~= "string" then
		return false
	end
	return #name >= 1 and #name <= Names.MAX_NAME and string.match(name, "^[%w_%.:%-]+$") ~= nil
end

-- Explains why a name is invalid, or nil when it is fine.
function Names.eventNameError(name: unknown): string?
	if type(name) ~= "string" or name == "" then
		return "nome vazio"
	end
	if #name > Names.MAX_NAME then
		return `nome com {#name} caracteres (máx. {Names.MAX_NAME})`
	end
	local bad = string.match(name, "[^%w_%.:%-]")
	if bad then
		return `caractere inválido '{bad}' (use A-Z a-z 0-9 _ . : -)`
	end
	return nil
end

function Names.isValidPropKey(key: unknown): boolean
	if type(key) ~= "string" then
		return false
	end
	return #key <= Names.MAX_NAME and string.match(key, "^[%a_][%w_]*$") ~= nil
end

-- Best-effort fix for user input: spaces and invalid characters become `_`, cut to 64.
function Names.sanitize(name: string): string
	local cleaned = string.gsub(name, "^%s+", "")
	cleaned = string.gsub(cleaned, "%s+$", "")
	cleaned = string.gsub(cleaned, "[^%w_%.:%-]", "_")
	return string.sub(cleaned, 1, Names.MAX_NAME)
end

-- Turns an event name into a Luau identifier usable in snippets (e.g. "boss.killed" -> "bossKilled").
function Names.identifier(name: string): string
	local out = string.gsub(name, "[^%w]+(%w?)", function(c: string)
		return string.upper(c)
	end)
	if out == "" or string.match(out, "^%d") then
		out = "event" .. out
	end
	return string.lower(string.sub(out, 1, 1)) .. string.sub(out, 2)
end

return Names

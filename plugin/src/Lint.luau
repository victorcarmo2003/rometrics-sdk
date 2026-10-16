--!strict
-- Validation. Pure: the caller collects tagged instances and script usages from the place.
local Names = require(script.Parent.Names)
local Registry = require(script.Parent.Registry)

local Lint = {}

export type Severity = "error" | "warning" | "info"

export type Issue = {
	severity: Severity,
	code: string,
	message: string,
	event: string?, -- registry event to open
	ref: any?, -- opaque target (Instance or script) handed back to the UI
	line: number?,
}

-- Snapshot of a tagged instance (built by Tagging.describe).
export type TaggedInfo = {
	ref: any,
	path: string,
	className: string,
	attributes: { [string]: any },
	isPart: boolean,
	isContainer: boolean, -- Model/Folder: Touched binds descendant parts
	hasParts: boolean,
	hasPrompt: boolean,
	hasDetector: boolean,
	isTool: boolean,
}

export type ScriptUsage = {
	ref: any,
	path: string,
	method: string,
	kind: string,
	name: string,
	line: number,
}

local SEVERITY_ORDER: { [Severity]: number } = { error = 1, warning = 2, info = 3 }

local VALID_TAG_TRIGGERS = { "Touched", "ProximityPrompt", "ClickDetector", "Activated" }

-- Trigger the SDK would infer (mirrors sdk/roblox/src/Tags.luau inferTrigger).
function Lint.inferTrigger(info: TaggedInfo): string?
	if info.className == "ProximityPrompt" then
		return "ProximityPrompt"
	elseif info.className == "ClickDetector" then
		return "ClickDetector"
	elseif info.isTool then
		return "Activated"
	elseif info.isPart or info.isContainer then
		return "Touched"
	end
	return nil
end

local function checkRegistry(registry: Registry.Registry, issues: { Issue })
	local seen: { [string]: string } = {}
	for _, event in registry.events do
		local nameError = Names.eventNameError(event.name)
		if nameError then
			table.insert(issues, {
				severity = "error",
				code = "invalid_name",
				message = `Evento '{event.name}': {nameError}`,
				event = event.name,
			})
		end
		local lower = string.lower(event.name)
		if seen[lower] then
			table.insert(issues, {
				severity = "error",
				code = "duplicate_name",
				message = `Evento '{event.name}' duplicado (também '{seen[lower]}')`,
				event = event.name,
			})
		else
			seen[lower] = event.name
		end
		local keys: { [string]: boolean } = {}
		for _, prop in event.props do
			if not Names.isValidPropKey(prop.key) then
				table.insert(issues, {
					severity = "error",
					code = "invalid_prop_key",
					message = `Evento '{event.name}': prop '{prop.key}' inválida (use letras, números e _)`,
					event = event.name,
				})
			elseif keys[prop.key] then
				table.insert(issues, {
					severity = "warning",
					code = "duplicate_prop",
					message = `Evento '{event.name}': prop '{prop.key}' repetida`,
					event = event.name,
				})
			end
			keys[prop.key] = true
		end
		if event.kind == "funnel" then
			if #event.steps == 0 then
				table.insert(issues, {
					severity = "warning",
					code = "funnel_no_steps",
					message = `Funil '{event.name}' sem passos`,
					event = event.name,
				})
			end
			local stepNames: { [string]: boolean } = {}
			for index, step in event.steps do
				if step.name == "" or #step.name > Names.MAX_NAME then
					table.insert(issues, {
						severity = "error",
						code = "invalid_step",
						message = `Funil '{event.name}': passo {index} com nome vazio ou acima de {Names.MAX_NAME} caracteres`,
						event = event.name,
					})
				elseif stepNames[string.lower(step.name)] then
					table.insert(issues, {
						severity = "warning",
						code = "duplicate_step",
						message = `Funil '{event.name}': passo '{step.name}' repetido`,
						event = event.name,
					})
				end
				stepNames[string.lower(step.name)] = true
				if step.event and not Registry.find(registry, step.event) then
					table.insert(issues, {
						severity = "warning",
						code = "step_event_unregistered",
						message = `Funil '{event.name}': passo '{step.name}' liga ao evento '{step.event}', que não está registrado`,
						event = event.name,
					})
				end
			end
		elseif #event.steps > 0 then
			table.insert(issues, {
				severity = "info",
				code = "steps_ignored",
				message = `Evento '{event.name}' ({event.kind}) tem passos, mas só funis usam passos`,
				event = event.name,
			})
		end
	end
end

local function checkTagged(registry: Registry.Registry, tagged: { TaggedInfo }, issues: { Issue })
	for _, info in tagged do
		local attrs = info.attributes
		local name = attrs.RM_Event
		if name == nil or name == "" then
			table.insert(issues, {
				severity = "error",
				code = "tag_missing_event",
				message = `{info.path}: tag RoMetrics sem RM_Event`,
				ref = info.ref,
			})
			continue
		end
		if not Names.isValidEventName(name) then
			table.insert(issues, {
				severity = "error",
				code = "tag_invalid_name",
				message = `{info.path}: RM_Event '{tostring(name)}' inválido ({Names.eventNameError(name) or "?"})`,
				ref = info.ref,
			})
			continue
		end
		local event = Registry.find(registry, name)
		if not event then
			table.insert(issues, {
				severity = "warning",
				code = "tag_unregistered",
				message = `{info.path}: evento '{name}' não está no registro (tag órfã)`,
				ref = info.ref,
			})
		elseif event.kind ~= "custom" then
			table.insert(issues, {
				severity = "warning",
				code = "tag_kind_mismatch",
				message = `{info.path}: '{name}' é {event.kind}; tags só enviam eventos custom`,
				ref = info.ref,
				event = event.name,
			})
		elseif event.trigger ~= "tag" then
			table.insert(issues, {
				severity = "info",
				code = "tag_trigger_code",
				message = `{info.path}: '{name}' está marcado como gatilho 'code' no registro, mas é usado por tag`,
				ref = info.ref,
				event = event.name,
			})
		end
		local rawTrigger = attrs.RM_Trigger
		local trigger: string?
		if rawTrigger == nil or rawTrigger == "" then
			trigger = Lint.inferTrigger(info)
			if not trigger then
				table.insert(issues, {
					severity = "error",
					code = "tag_no_trigger",
					message = `{info.path}: não dá para inferir o gatilho de um {info.className}; defina RM_Trigger`,
					ref = info.ref,
				})
			end
		elseif not table.find(VALID_TAG_TRIGGERS, tostring(rawTrigger)) then
			table.insert(issues, {
				severity = "error",
				code = "tag_bad_trigger",
				message = `{info.path}: RM_Trigger '{tostring(rawTrigger)}' não suportado`,
				ref = info.ref,
			})
		else
			trigger = tostring(rawTrigger)
		end
		if trigger == "Touched" and not info.isPart and not info.hasParts and not info.isContainer then
			table.insert(issues, {
				severity = "error",
				code = "tag_no_target",
				message = `{info.path}: Touched precisa de uma BasePart (ou Model/Folder com partes)`,
				ref = info.ref,
			})
		elseif trigger == "ProximityPrompt" and not info.hasPrompt then
			table.insert(issues, {
				severity = "warning",
				code = "tag_no_target",
				message = `{info.path}: nenhum ProximityPrompt na instância (o SDK espera um aparecer)`,
				ref = info.ref,
			})
		elseif trigger == "ClickDetector" and not info.hasDetector then
			table.insert(issues, {
				severity = "warning",
				code = "tag_no_target",
				message = `{info.path}: nenhum ClickDetector na instância (o SDK espera um aparecer)`,
				ref = info.ref,
			})
		elseif trigger == "Activated" and not info.isTool then
			table.insert(issues, {
				severity = "error",
				code = "tag_no_target",
				message = `{info.path}: Activated só funciona em Tool`,
				ref = info.ref,
			})
		end
		for key in attrs do
			if string.sub(key, 1, 8) == "RM_Prop_" and not Names.isValidPropKey(string.sub(key, 9)) then
				table.insert(issues, {
					severity = "warning",
					code = "tag_bad_prop",
					message = `{info.path}: atributo {key} tem chave de prop inválida`,
					ref = info.ref,
				})
			end
		end
	end
end

local function checkUsages(registry: Registry.Registry, usages: { ScriptUsage }, issues: { Issue })
	for _, usage in usages do
		if not Names.isValidEventName(usage.name) then
			table.insert(issues, {
				severity = "error",
				code = "usage_invalid_name",
				message = `{usage.path}:{usage.line}: {usage.method}("{usage.name}") nome inválido`,
				ref = usage.ref,
				line = usage.line,
			})
			continue
		end
		local event = Registry.find(registry, usage.name)
		if not event then
			table.insert(issues, {
				severity = "warning",
				code = "usage_unregistered",
				message = `{usage.path}:{usage.line}: '{usage.name}' usado em {usage.method} mas não registrado`,
				ref = usage.ref,
				line = usage.line,
			})
		elseif event.kind ~= usage.kind then
			table.insert(issues, {
				severity = "warning",
				code = "usage_kind_mismatch",
				message = `{usage.path}:{usage.line}: '{usage.name}' é {event.kind} no registro, mas usado em {usage.method}`,
				ref = usage.ref,
				line = usage.line,
				event = event.name,
			})
		end
	end
end

local function checkUnused(
	registry: Registry.Registry,
	tagged: { TaggedInfo },
	usages: { ScriptUsage },
	issues: { Issue }
)
	local used: { [string]: boolean } = {}
	for _, info in tagged do
		if type(info.attributes.RM_Event) == "string" then
			used[string.lower(info.attributes.RM_Event)] = true
		end
	end
	for _, usage in usages do
		used[string.lower(usage.name)] = true
	end
	for _, event in registry.events do
		for _, step in event.steps do
			if step.event then
				used[string.lower(step.event)] = true
			end
		end
	end
	for _, event in registry.events do
		if not used[string.lower(event.name)] then
			table.insert(issues, {
				severity = "info",
				code = "unused",
				message = `Evento '{event.name}' registrado mas não usado em scripts nem tags`,
				event = event.name,
			})
		end
	end
end

function Lint.run(registry: Registry.Registry, tagged: { TaggedInfo }, usages: { ScriptUsage }): { Issue }
	local issues: { Issue } = {}
	checkRegistry(registry, issues)
	checkTagged(registry, tagged, issues)
	checkUsages(registry, usages, issues)
	checkUnused(registry, tagged, usages, issues)
	-- Stable sort by severity, keeping discovery order inside a severity.
	for index, issue in issues do
		(issue :: any)._order = index
	end
	table.sort(issues, function(a, b)
		local sa, sb = SEVERITY_ORDER[a.severity], SEVERITY_ORDER[b.severity]
		if sa ~= sb then
			return sa < sb
		end
		return (a :: any)._order < (b :: any)._order
	end)
	return issues
end

function Lint.counts(issues: { Issue }): { error: number, warning: number, info: number }
	local counts = { error = 0, warning = 0, info = 0 }
	for _, issue in issues do
		counts[issue.severity] += 1
	end
	return counts
end

return Lint

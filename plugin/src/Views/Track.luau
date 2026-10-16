--!strict
-- "Rastrear": tag the Explorer selection with RM_* attributes (events without code).
local Lint = require(script.Parent.Parent.Lint)
local Names = require(script.Parent.Parent.Names)
local Registry = require(script.Parent.Parent.Registry)
local Studio = require(script.Parent.Parent.Studio)
local Tagging = require(script.Parent.Parent.Tagging)
local Theme = require(script.Parent.Parent.Theme)
local UI = require(script.Parent.Parent.UI)

type Draft = {
	event: string,
	trigger: string?,
	value: number?,
	cooldown: number?,
	once: boolean,
	props: { { key: string, value: string } },
}

type State = {
	search: string,
	draft: Draft?,
	draftFor: Instance?,
	lastEvent: string,
}

local function getState(app: any): State
	local state = app.state.track
	if not state then
		state = { search = "", draft = nil, draftFor = nil, lastEvent = "" }
		app.state.track = state
	end
	return state
end

local function draftFrom(instance: Instance?, fallbackEvent: string): Draft
	local spec = if instance then Tagging.read(instance) else nil
	if not spec then
		return { event = fallbackEvent, trigger = nil, value = nil, cooldown = nil, once = false, props = {} }
	end
	local props = {}
	for key, value in spec.props do
		table.insert(props, { key = key, value = tostring(value) })
	end
	table.sort(props, function(a, b)
		return a.key < b.key
	end)
	return {
		event = spec.event,
		trigger = spec.trigger,
		value = spec.value,
		cooldown = spec.cooldown,
		once = spec.once,
		props = props,
	}
end

-- Adds schema keys from the registry that the draft does not have yet.
local function seedProps(draft: Draft, event: Registry.EventDef?)
	if not event then
		return
	end
	for _, prop in event.props do
		local present = false
		for _, row in draft.props do
			if row.key == prop.key then
				present = true
			end
		end
		if not present then
			table.insert(draft.props, { key = prop.key, value = "" })
		end
	end
end

local function coerce(raw: string, propType: string?): any
	if propType == "number" or (propType == nil and tonumber(raw) ~= nil) then
		return tonumber(raw) or 0
	elseif propType == "boolean" then
		return raw == "true" or raw == "1"
	end
	return raw
end

local View = {
	id = "track",
	title = "Marcar objeto (sem código)",
	watches = { selection = true, tags = true },
}

function View.render(app: any, container: Frame)
	local state = getState(app)
	local p = UI.palette
	local left, main = app:split(container)
	local selection = Studio.selection()
	local first = selection[1]
	if state.draftFor ~= first or not state.draft then
		state.draft = draftFrom(first, state.lastEvent)
		state.draftFor = first
	end
	local draft = state.draft :: Draft

	-- Sidebar: tracked instances ---------------------------------------------------------------------
	local listFrame = UI.scroll({ Position = UDim2.fromOffset(0, 72), Size = UDim2.new(1, 0, 1, -72) }, 1, 6)
	local function renderList()
		UI.clear(listFrame)
		local query = string.lower(state.search)
		local tagged = Tagging.tagged()
		local shown = 0
		for _, instance in tagged do
			local event = instance:GetAttribute("RM_Event")
			local label = `{instance.Name}`
			local haystack = string.lower(instance:GetFullName() .. " " .. tostring(event))
			if query ~= "" and not string.find(haystack, query, 1, true) then
				continue
			end
			shown += 1
			local registered = type(event) == "string" and Registry.find(app.registry, event) ~= nil
			UI.listRow(label, {
				selected = table.find(selection, instance) ~= nil,
				right = { UI.badge(tostring(event or "?"), if registered then p.accent else p.warning) },
				onClick = function()
					Studio.select({ instance })
				end,
			}).Parent =
				listFrame
		end
		if shown == 0 then
			UI.label(
				if #tagged == 0 then "Nenhuma instância rastreada." else "Nada encontrado.",
				{ color = p.dimText }
			).Parent =
				listFrame
		end
	end
	local highlightRow = UI.row(8, {
		UI.toggle(app.settings:get("highlight"), function(value)
			app.settings:set("highlight", value)
			app.highlighter:setEnabled(value)
		end),
		UI.label("Destacar no viewport", { color = p.subText, size = 13, autoX = true }),
	})
	local top = UI.column(6, {
		UI.input({
			text = state.search,
			placeholder = "Buscar instâncias/eventos…",
			onChange = function(text)
				state.search = text
				renderList()
			end,
		}),
		highlightRow,
	}, { Size = UDim2.new(1, 0, 0, 72), AutomaticSize = Enum.AutomaticSize.None })
	UI.padding(8, 8, 0, 8).Parent = top
	top.Parent = left
	listFrame.Parent = left
	renderList()

	-- Main ------------------------------------------------------------------------------------------
	local scroller = UI.scroll({ Parent = main }, 10, 12)
	local renderMain: () -> ()

	local function apply(spec: Tagging.Spec)
		local err = Tagging.apply(selection, spec)
		if err then
			app:toast(`Falha: {err}`, "error")
		else
			state.lastEvent = spec.event
			state.draftFor = nil
			app:toast(`{#selection} instância(s) rastreando {spec.event}`, "success")
		end
	end

	local function buildSpec(): Tagging.Spec?
		local name = Names.sanitize(draft.event)
		local nameError = Names.eventNameError(name)
		if nameError then
			app:toast(`Evento: {nameError}`, "error")
			return nil
		end
		local event = Registry.find(app.registry, name)
		local schema: { [string]: string } = {}
		if event then
			for _, prop in event.props do
				schema[prop.key] = prop.type
			end
		end
		local props: { [string]: any } = {}
		for _, row in draft.props do
			if row.key ~= "" and row.value ~= "" then
				if not Names.isValidPropKey(row.key) then
					app:toast(`Prop inválida: {row.key}`, "error")
					return nil
				end
				props[row.key] = coerce(row.value, schema[row.key])
			end
		end
		return {
			event = if event then event.name else name,
			trigger = draft.trigger,
			value = draft.value,
			cooldown = draft.cooldown,
			once = draft.once,
			props = props,
		}
	end

	local function onApply()
		if #selection == 0 then
			return
		end
		local spec = buildSpec()
		if not spec then
			return
		end
		local event = Registry.find(app.registry, spec.event)
		if event then
			apply(spec)
			return
		end
		UI.dialog({
			title = `'{spec.event}' não está no registro`,
			message = "Registrar como evento custom com gatilho por tag? Sem registro a Validação aponta tag órfã.",
			buttons = {
				{ text = "Cancelar", variant = "secondary" },
				{
					text = "Só aplicar",
					variant = "secondary",
					onClick = function()
						apply(spec)
					end,
				},
				{
					text = "Registrar e aplicar",
					variant = "primary",
					onClick = function()
						local registry = Registry.clone(app.registry)
						local newEvent = Registry.newEvent(spec.event)
						newEvent.trigger = "tag"
						for key, value in spec.props do
							local t = type(value)
							table.insert(
								newEvent.props,
								{ key = key, type = if t == "number" or t == "boolean" then t else "string" } :: any
							)
						end
						Registry.add(registry, newEvent)
						-- One undo step for both the registry and the tags.
						app:saveRegistry(registry, `rastrear {spec.event}`, function()
							for _, instance in selection do
								Tagging.apply({ instance }, spec)
							end
						end)
						state.lastEvent = spec.event
						state.draftFor = nil
					end,
				},
			},
		})
	end

	renderMain = function()
		UI.clear(scroller)
		-- Selection summary
		local selPanel, sel = UI.section(`Seleção ({#selection})`)
		if #selection == 0 then
			UI.label(
				"Selecione no Explorer uma BasePart/Model (Touched), ProximityPrompt, ClickDetector ou Tool (Activated).",
				{ wrap = true, color = p.subText }
			).Parent =
				sel
		else
			for index, instance in selection do
				if index > 6 then
					UI.label(`… e mais {#selection - 6}`, { color = p.dimText, size = 12 }).Parent = sel
					break
				end
				local info = Tagging.describe(instance)
				local inferred = Lint.inferTrigger(info)
				UI.row(6, {
					UI.label(instance:GetFullName(), { color = p.text, size = 13 }),
					UI.badge(instance.ClassName, p.subText),
					if inferred then UI.badge(inferred, p.accent) else UI.badge("sem gatilho", p.warning),
				}).Parent =
					sel
			end
		end
		selPanel.Parent = scroller
		if #selection == 0 then
			return
		end

		-- Controls
		local controlsPanel, controls = UI.section("Opções")
		local eventOptions = {}
		for _, event in Registry.byKind(app.registry, "custom") do
			table.insert(eventOptions, {
				label = if event.trigger == "tag" then `{event.name}  ·  tag` else event.name,
				value = event.name,
			})
		end
		table.insert(eventOptions, { label = "+ Digitar nome…", value = "__new" })
		UI.controlRow(
			"Evento",
			UI.dropdown({
				options = eventOptions,
				value = if draft.event ~= "" then draft.event else nil,
				placeholder = if draft.event ~= "" then draft.event else "Escolher evento…",
				onChange = function(value)
					if value == "__new" then
						UI.prompt(
							"Nome do evento",
							"Eventos novos podem ser registrados ao aplicar.",
							draft.event,
							function(text)
								draft.event = Names.sanitize(text)
								seedProps(draft, (Registry.find(app.registry, draft.event)))
								renderMain()
							end
						)
						return
					end
					draft.event = value
					seedProps(draft, (Registry.find(app.registry, value)))
					renderMain()
				end,
			}),
			if draft.event ~= "" and not Registry.find(app.registry, draft.event)
				then "Não registrado: ao aplicar o plugin oferece registrar."
				else nil
		).Parent =
			controls

		local triggerOptions = {}
		for _, trigger in Names.TAG_TRIGGERS do
			table.insert(triggerOptions, {
				label = if trigger == "Auto" then "Auto (pela classe)" else trigger,
				value = if trigger == "Auto" then nil else trigger,
			})
		end
		UI.controlRow(
			"Gatilho",
			UI.dropdown({
				options = triggerOptions,
				value = draft.trigger,
				placeholder = "Auto (pela classe)",
				onChange = function(value)
					draft.trigger = value
					renderMain()
				end,
			}),
			"GuiButton ainda não é suportado (precisa do bridge cliente; F2)."
		).Parent =
			controls
		UI.controlRow(
			"Valor",
			UI.number(draft.value, {
				allowEmpty = true,
				onChange = function(value)
					draft.value = value
				end,
			}),
			"Opcional: `value` do evento."
		).Parent =
			controls
		UI.controlRow(
			"Cooldown (s)",
			UI.number(draft.cooldown, {
				min = 0,
				allowEmpty = true,
				onChange = function(value)
					draft.cooldown = value
				end,
			}),
			"Por jogador e instância. Touched usa no mínimo 1 s."
		).Parent =
			controls
		UI.controlRow(
			"Uma vez",
			UI.row(8, {
				UI.toggle(draft.once, function(value)
					draft.once = value
				end),
				UI.label("por sessão do jogador", { color = p.dimText, size = 13, autoX = true }),
			})
		).Parent =
			controls
		controlsPanel.Parent = scroller

		-- Props
		local addProp = UI.button("+ Prop", {
			variant = "ghost",
			onClick = function()
				table.insert(draft.props, { key = "", value = "" })
				renderMain()
			end,
		})
		local propsPanel, props = UI.section("Props (RM_Prop_*)", { addProp })
		if #draft.props == 0 then
			UI.label("Sem props extras. O SDK já envia trigger e instance.", { color = p.dimText }).Parent = props
		end
		for index, row in draft.props do
			local keyBox = UI.input({
				text = row.key,
				placeholder = "chave",
				onCommit = function(text)
					row.key = text
				end,
			})
			keyBox.Size = UDim2.new(0.4, -20, 1, 0)
			local valueBox = UI.input({
				text = row.value,
				placeholder = "valor",
				onCommit = function(text)
					row.value = text
				end,
			})
			valueBox.Size = UDim2.new(0.6, -20, 1, 0)
			UI.row(6, {
				keyBox,
				valueBox,
				UI.button("×", {
					width = 26,
					variant = "ghost",
					onClick = function()
						table.remove(draft.props, index)
						renderMain()
					end,
				}),
			}).Parent =
				props
		end
		propsPanel.Parent = scroller

		local anyTagged = false
		for _, instance in selection do
			if Tagging.isTagged(instance) then
				anyTagged = true
			end
		end
		local actions: { Instance } = {
			UI.button(`Aplicar a {#selection}`, { variant = "primary", onClick = onApply }),
		}
		if anyTagged then
			table.insert(
				actions,
				UI.button("Remover rastreio", {
					variant = "danger",
					onClick = function()
						local err = Tagging.remove(selection)
						if err then
							app:toast(err, "error")
						else
							state.draftFor = nil
							app:toast("Rastreio removido (Ctrl+Z desfaz)", "success")
						end
					end,
				})
			)
		end
		UI.row(8, actions).Parent = scroller
		local note =
			UI.label("Tudo aqui entra no histórico: Ctrl+Z desfaz.", { color = p.dimText, size = Theme.SMALL_SIZE })
		note.Parent = scroller
	end

	renderMain()
end

return View

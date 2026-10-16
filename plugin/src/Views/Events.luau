--!strict
-- "Eventos": registry tree (search, grouped by kind) + event editor + where it is used.
local Flow = require(script.Parent.Parent.Flow)
local Names = require(script.Parent.Parent.Names)
local Registry = require(script.Parent.Parent.Registry)
local Studio = require(script.Parent.Parent.Studio)
local Tagging = require(script.Parent.Parent.Tagging)
local Theme = require(script.Parent.Parent.Theme)
local UI = require(script.Parent.Parent.UI)

local KIND_LABELS = {
	custom = "Custom",
	funnel = "Funis",
	progression = "Progressão",
	economy = "Economia",
}
local MAX_ROWS_PER_KIND = 200

type State = {
	search: string,
	selected: string?,
	draft: Registry.EventDef?,
	isNew: boolean,
	collapsed: { [string]: boolean },
}

local function cloneEvent(event: Registry.EventDef): Registry.EventDef
	local registry = Registry.empty()
	table.insert(registry.events, event)
	return Registry.clone(registry).events[1]
end

local function getState(app: any): State
	local state = app.state.events
	if not state then
		state = { search = "", selected = nil, draft = nil, isNew = false, collapsed = {} }
		app.state.events = state
	end
	return state
end

local View = {
	id = "events",
	title = "Eventos",
	watches = { tags = true },
}

function View.render(app: any, container: Frame)
	local state = getState(app)
	local p = UI.palette
	local left, main = app:split(container)
	local renderMain: () -> ()

	local function selectEvent(name: string?)
		state.selected = name
		state.isNew = false
		local event = if name then Registry.find(app.registry, name) else nil
		state.draft = if event then cloneEvent(event) else nil
	end

	-- Re-select by name after reloads (draft survives unless the event changed underneath).
	if state.selected and not state.isNew then
		local event = Registry.find(app.registry, state.selected)
		if not event then
			selectEvent(nil)
		elseif not state.draft then
			state.draft = cloneEvent(event)
		end
	end

	-- Sidebar ---------------------------------------------------------------------------------------
	local listFrame = UI.scroll({ Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 1, -70) }, 1, 6)
	local function renderList()
		UI.clear(listFrame)
		local query = string.lower(state.search)
		local order = 0
		for _, kind in Names.KINDS do
			local events = {}
			for _, event in Registry.byKind(app.registry, kind :: any) do
				if query == "" or string.find(string.lower(event.name), query, 1, true) then
					table.insert(events, event)
				end
			end
			if #events == 0 and query ~= "" then
				continue
			end
			local collapsed = state.collapsed[kind] == true
			order += 1
			local header = UI.listRow(KIND_LABELS[kind], {
				prefix = { UI.chevron(not collapsed) },
				font = Theme.FONT_BOLD,
				color = p.subText,
				height = 24,
				right = { UI.label(tostring(#events), { size = Theme.SMALL_SIZE, color = p.dimText, autoX = true }) },
				onClick = function()
					state.collapsed[kind] = not collapsed
					renderList()
				end,
			})
			header.LayoutOrder = order
			header.Parent = listFrame
			if collapsed then
				continue
			end
			for index, event in events do
				-- Big registries: cap rows per group so search/typing stays responsive.
				if index > MAX_ROWS_PER_KIND then
					order += 1
					local more = UI.label(`… mais {#events - MAX_ROWS_PER_KIND} (use a busca)`, {
						size = Theme.SMALL_SIZE,
						color = p.dimText,
						wrap = true,
					})
					more.LayoutOrder = order
					more.Parent = listFrame
					break
				end
				order += 1
				local selected = state.selected ~= nil and string.lower(state.selected) == string.lower(event.name)
				local row = UI.listRow(event.name, {
					selected = selected,
					indent = 14,
					prefix = {
						UI.new("Frame", {
							BackgroundColor3 = Theme.kindColor(event.kind),
							Size = UDim2.fromOffset(6, 6),
						}, { UI.corner(3) }),
					},
					right = if event.trigger == "tag" then { UI.badge("TAG", p.accent) } else nil,
					onClick = function()
						selectEvent(event.name)
						renderList()
						renderMain()
					end,
				})
				row.LayoutOrder = order
				row.Parent = listFrame
			end
		end
		if #app.registry.events == 0 then
			local empty = UI.label("Nenhum evento registrado.", { color = p.dimText, wrap = true })
			empty.LayoutOrder = order + 1
			empty.Parent = listFrame
		end
	end

	local top = UI.column(6, {
		UI.input({
			text = state.search,
			placeholder = "Buscar eventos…",
			onChange = function(text)
				state.search = text
				renderList()
			end,
		}),
		UI.row(6, {
			UI.button("+ Novo evento", {
				variant = "primary",
				onClick = function()
					state.selected = nil
					state.isNew = true
					state.draft = Registry.newEvent("")
					renderList()
					renderMain()
				end,
			}),
			UI.button("Recarregar", {
				onClick = function()
					app:reloadRegistry()
				end,
			}),
		}),
	}, { Size = UDim2.new(1, 0, 0, 70) })
	UI.padding(8, 8, 0, 8).Parent = top
	top.AutomaticSize = Enum.AutomaticSize.None
	top.Parent = left
	listFrame.Parent = left
	renderList()

	-- Main ------------------------------------------------------------------------------------------
	local scroller = UI.scroll({ Parent = main }, 10, 12)

	local function save()
		local draft = state.draft
		if not draft then
			return
		end
		draft.name = Names.sanitize(draft.name)
		if draft.kind ~= "custom" then
			draft.trigger = "code"
		end
		local registry = Registry.clone(app.registry)
		local err
		if state.isNew then
			err = Registry.add(registry, draft)
		else
			err = Registry.upsert(registry, draft, state.selected)
		end
		if err then
			app:toast(err, "error")
			return
		end
		state.selected = draft.name
		state.isNew = false
		state.draft = nil
		app:saveRegistry(registry, `evento {draft.name}`)
	end

	local function rename(from: string)
		UI.prompt(
			"Renomear evento",
			`Novo nome para '{from}'. Instâncias marcadas são atualizadas.`,
			from,
			function(text)
				local to = Names.sanitize(text)
				if to == from then
					return
				end
				local nameError = Names.eventNameError(to)
				if nameError then
					app:toast(nameError, "error")
					return
				end
				local registry = Registry.clone(app.registry)
				local err = Registry.rename(registry, from, to)
				if err then
					app:toast(err, "error")
					return
				end
				local tagged = Tagging.withEvent(from)
				local usages = {}
				for _, usage in app:usages(true) do
					if string.lower(usage.name) == string.lower(from) then
						table.insert(usages, usage)
					end
				end
				local body: { Instance } = {}
				if #usages > 0 then
					table.insert(
						body,
						UI.label(
							`{#usages} ocorrência(s) em scripts NÃO serão reescritas — ajuste o código depois:`,
							{ wrap = true, color = p.warning }
						)
					)
					for index, usage in usages do
						if index > 8 then
							table.insert(body, UI.label(`… e mais {#usages - 8}`, { color = p.dimText, size = 12 }))
							break
						end
						table.insert(
							body,
							UI.label(
								`{usage.path}:{usage.line}`,
								{ font = Theme.FONT_CODE, size = 12, color = p.subText }
							)
						)
					end
				end
				UI.confirm(
					"Confirmar renomeação",
					`'{from}' → '{to}'. {#tagged} instância(s) marcada(s) serão atualizadas.`,
					"Renomear",
					function()
						state.selected = to
						state.draft = nil
						app:saveRegistry(registry, `renomear {from} → {to}`, function()
							Tagging.renameEvent(from, to)
						end)
					end,
					false,
					body
				)
			end
		)
	end

	local function remove(name: string)
		local tagged = Tagging.withEvent(name)
		local buttons: { UI.DialogButton } = {
			{ text = "Cancelar", variant = "secondary" },
			{
				text = "Remover do registro",
				variant = "danger",
				onClick = function()
					local registry = Registry.clone(app.registry)
					Registry.remove(registry, name)
					selectEvent(nil)
					app:saveRegistry(registry, `remover {name}`)
				end,
			},
		}
		if #tagged > 0 then
			table.insert(buttons, {
				text = `Remover e desmarcar {#tagged}`,
				variant = "danger",
				onClick = function()
					local registry = Registry.clone(app.registry)
					Registry.remove(registry, name)
					selectEvent(nil)
					app:saveRegistry(registry, `remover {name}`, function()
						for _, instance in tagged do
							instance:RemoveTag(Tagging.TAG)
							for key in instance:GetAttributes() do
								if string.sub(key, 1, 3) == "RM_" then
									instance:SetAttribute(key, nil)
								end
							end
						end
					end)
				end,
			})
		end
		UI.dialog({
			title = `Remover '{name}'?`,
			message = if #tagged > 0
				then `{#tagged} instância(s) usam este evento. Sem desmarcar, elas viram tags órfãs (a Validação aponta).`
				else "Ocorrências em scripts continuam no código.",
			buttons = buttons,
		})
	end

	local function usageSection(event: Registry.EventDef): Frame
		local refresh = UI.button("Reescanear", {
			variant = "ghost",
			onClick = function()
				app:usages(true)
				renderMain()
			end,
		})
		local panel, body = UI.section("Onde é usado", { refresh })
		local any = false
		for _, instance in Tagging.withEvent(event.name) do
			any = true
			UI.listRow(instance:GetFullName(), {
				prefix = { UI.badge("TAG", p.accent) },
				onClick = function()
					Studio.select({ instance })
				end,
			}).Parent =
				body
		end
		for _, usage in app:usages() do
			if string.lower(usage.name) == string.lower(event.name) then
				any = true
				UI.listRow(`{usage.path}:{usage.line}  {usage.method}`, {
					prefix = { UI.badge("CODE", p.success) },
					onClick = function()
						Studio.openScript(app.plugin, usage.ref, usage.line)
					end,
				}).Parent =
					body
			end
		end
		for _, ref in Flow.usagesOf(app.registry, event.name) do
			any = true
			UI.listRow(`Funil {ref.funnel}, passo {ref.step}`, {
				prefix = { UI.badge("FLOW", Theme.kindColor("funnel")) },
				onClick = function()
					app.state.flows = { selected = ref.funnel }
					app:setTab("flows")
				end,
			}).Parent =
				body
		end
		if not any then
			UI.label("Nenhum uso encontrado em tags, scripts ou funis.", { color = p.dimText }).Parent = body
		end
		return panel
	end

	renderMain = function()
		UI.clear(scroller)
		local draft = state.draft
		if not draft then
			local panel, body = UI.section("Registro de eventos")
			UI.label(
				"Selecione um evento à esquerda ou crie um novo. O registro fica em ReplicatedStorage."
					.. Registry.MODULE_NAME
					.. " e é lido pelo plugin e pelo SDK.",
				{ wrap = true, color = p.subText }
			).Parent =
				body
			for _, note in app.registryNotes do
				UI.label("Aviso: " .. note, { wrap = true, color = p.warning, size = 12 }).Parent = body
			end
			panel.Parent = scroller
			return
		end
		local current = draft :: Registry.EventDef

		-- Title row
		local title = UI.row(8, {
			UI.new(
				"Frame",
				{ BackgroundColor3 = Theme.kindColor(current.kind), Size = UDim2.fromOffset(10, 10) },
				{ UI.corner(5) }
			),
			UI.label(
				if state.isNew then "Novo evento" else current.name,
				{ font = Theme.FONT_BOLD, size = 18, autoX = true }
			),
			UI.badge(string.upper(current.kind), Theme.kindColor(current.kind)),
		}, { Size = UDim2.new(1, 0, 0, 30) })
		title.Parent = scroller

		-- Definition
		local defPanel, def = UI.section("Definição")
		if state.isNew then
			UI.controlRow(
				"Nome",
				UI.input({
					text = current.name,
					placeholder = "ex.: BossKilled",
					onCommit = function(text)
						current.name = text
					end,
				}),
				"A-Z a-z 0-9 _ . : -  (até 64). Funil = nome do funil; economia = moeda; progressão = caminho."
			).Parent =
				def
		end
		local kindOptions = {}
		for _, kind in Names.KINDS do
			table.insert(kindOptions, { label = KIND_LABELS[kind], value = kind })
		end
		UI.controlRow(
			"Tipo",
			UI.dropdown({
				options = kindOptions,
				value = current.kind,
				onChange = function(value)
					current.kind = value
					renderMain()
				end,
			})
		).Parent =
			def
		if current.kind == "custom" then
			UI.controlRow(
				"Gatilho",
				UI.dropdown({
					options = {
						{ label = "Código (LogCustomEvent/track)", value = "code" },
						{ label = "Tag em instância (sem código)", value = "tag" },
					},
					value = current.trigger,
					onChange = function(value)
						current.trigger = value
					end,
				})
			).Parent =
				def
		end
		UI.controlRow(
			"Descrição",
			UI.input({
				text = current.description,
				placeholder = "O que este evento mede?",
				multiline = true,
				height = 48,
				onCommit = function(text)
					current.description = text
				end,
			})
		).Parent =
			def
		defPanel.Parent = scroller

		-- Props schema
		local addProp = UI.button("+ Prop", {
			variant = "ghost",
			onClick = function()
				table.insert(current.props, { key = "", type = "string" })
				renderMain()
			end,
		})
		local propsPanel, props = UI.section("Props (customFields)", { addProp })
		if #current.props == 0 then
			UI.label(
				"Sem props. Props viram customFields / RM_Prop_* e somam até ~2 KB.",
				{ color = p.dimText, wrap = true }
			).Parent =
				props
		end
		for index, prop in current.props do
			local keyBox = UI.input({
				text = prop.key,
				placeholder = "chave",
				onCommit = function(text)
					prop.key = text
				end,
			})
			keyBox.Size = UDim2.fromScale(0, 1)
			UI.flex().Parent = keyBox
			UI.row(6, {
				keyBox,
				UI.dropdown({
					options = {
						{ label = "string", value = "string" },
						{ label = "number", value = "number" },
						{ label = "boolean", value = "boolean" },
					},
					value = prop.type,
					width = 100,
					onChange = function(value)
						prop.type = value
					end,
				}),
				UI.button("×", {
					width = 26,
					variant = "ghost",
					onClick = function()
						table.remove(current.props, index)
						renderMain()
					end,
				}),
			}).Parent =
				props
		end
		propsPanel.Parent = scroller

		if current.kind == "funnel" then
			local flowPanel, flow = UI.section("Passos do funil")
			local names = {}
			for _, step in current.steps do
				table.insert(names, step.name)
			end
			UI.label(
				if #names > 0 then table.concat(names, "  →  ") else "Nenhum passo ainda.",
				{ wrap = true, color = p.subText }
			).Parent =
				flow
			UI.button("Editar na aba Fluxos", {
				onClick = function()
					app.state.flows = { selected = current.name }
					app:setTab("flows")
				end,
			}).Parent =
				flow
			flowPanel.Parent = scroller
		end

		-- Actions
		local actions: { Instance } = {
			UI.button(if state.isNew then "Criar" else "Salvar", { variant = "primary", onClick = save }),
			UI.button("Descartar", {
				onClick = function()
					if state.isNew then
						selectEvent(nil)
					else
						selectEvent(state.selected)
					end
					renderList()
					renderMain()
				end,
			}),
		}
		if not state.isNew and state.selected then
			local name = state.selected :: string
			table.insert(
				actions,
				UI.button("Renomear", {
					onClick = function()
						rename(name)
					end,
				})
			)
			table.insert(
				actions,
				UI.button("Snippet", {
					onClick = function()
						app.state.snippets =
							{ event = name, id = if current.kind == "custom" then "custom" else current.kind }
						app:setTab("snippets")
					end,
				})
			)
			table.insert(
				actions,
				UI.button("Remover", {
					variant = "danger",
					onClick = function()
						remove(name)
					end,
				})
			)
		end
		UI.row(8, actions).Parent = scroller

		if not state.isNew then
			usageSection(current).Parent = scroller
		end
	end

	renderMain()
end

return View

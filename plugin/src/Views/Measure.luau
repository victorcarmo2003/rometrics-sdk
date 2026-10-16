--!strict
-- "Medir": "o que você quer medir?" cards, then one short assistant per kind. Each assistant shows
-- the generated line live, lets the user pick where it goes (cursor line or end of the selected
-- script), inserts it and registers the event, all in one undo step.
local Codegen = require(script.Parent.Parent.Codegen)
local Names = require(script.Parent.Parent.Names)
local Placement = require(script.Parent.Parent.Placement)
local Registry = require(script.Parent.Parent.Registry)
local Studio = require(script.Parent.Parent.Studio)
local Theme = require(script.Parent.Parent.Theme)
local UI = require(script.Parent.Parent.UI)

local View = {
	id = "measure",
	title = "Medir",
	nav = true,
	watches = {},
}

type Mode = "economy" | "custom" | "funnel" | "progression"

type State = {
	mode: Mode?,
	event: string?, -- prefill from "Eventos"
	placement: Placement.State,
	form: { [string]: any },
}

local function getState(app: any): State
	local state = app.state.measure
	if not state then
		state = {}
		app.state.measure = state
	end
	state.placement = state.placement or {}
	state.form = state.form or {}
	return state :: State
end

-- Prop types from what the user typed (registry schema for the "Eventos" tab).
local function inferType(value: string): Registry.PropType
	local trimmed = string.gsub(value, "^%s+", "")
	if tonumber(trimmed) ~= nil then
		return "number"
	elseif trimmed == "true" or trimmed == "false" then
		return "boolean"
	end
	return "string"
end

local function textInput(form: { [string]: any }, key: string, placeholder: string, refresh: () -> (), code: boolean?): any
	return UI.input({
		text = form[key] or "",
		placeholder = placeholder,
		code = code,
		onChange = function(text)
			form[key] = text
			refresh()
		end,
	})
end

-- Quick-pick chips for names already in the registry.
local function chips(names: { string }, onPick: (name: string) -> ()): any?
	if #names == 0 then
		return nil
	end
	local row = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(120, 24),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	for index, name in names do
		if index > 8 then
			break
		end
		local chip = UI.button(name, {
			variant = "secondary",
			height = 24,
			onClick = function()
				onPick(name)
			end,
		})
		chip.TextSize = 12
		chip.TextTruncate = Enum.TextTruncate.AtEnd
		chip.Parent = row
	end
	return row
end

local function namesOf(app: any, kind: Registry.Kind): { string }
	local out = {}
	for _, event in Registry.byKind(app.registry, kind) do
		table.insert(out, event.name)
	end
	return out
end

-- Assistant page frame: back link, title, explanation, form, preview, placement, insert button.
type Assistant = {
	title: string,
	intro: string,
	fields: (form: { [string]: any }, column: any, refresh: () -> ()) -> (),
	build: (form: { [string]: any }, sdk: string) -> string,
	-- Validates and returns the registry to save with the insertion (or an error message).
	register: (form: { [string]: any }) -> (Registry.Registry?, string?),
	label: (form: { [string]: any }) -> string,
}

local function renderAssistant(app: any, state: State, scroller: any, assistant: Assistant)
	local p = UI.palette
	local form = state.form

	UI.link("‹  Outras opções", function()
		state.mode = nil
		state.form = {}
		app:render()
	end).Parent =
		scroller
	UI.heading(assistant.title, assistant.intro).Parent = scroller

	local refreshers: { () -> () } = {}
	local function refresh()
		for _, fn in refreshers do
			fn()
		end
	end

	local step1 = UI.card(nil, { gap = 12 })
	UI.label("1 · PREENCHA", { font = Theme.FONT_BOLD, size = 11, color = p.accent, height = 16 }).Parent = step1
	assistant.fields(form, step1, refresh)
	step1.Parent = scroller

	local step2 = UI.card(nil, { gap = 8 })
	UI.label("2 · CONFIRA O CÓDIGO", { font = Theme.FONT_BOLD, size = 11, color = p.accent, height = 16 }).Parent = step2
	local preview, update = Placement.preview(function()
		local ok, code = pcall(assistant.build, form, "RoMetrics")
		return if ok then code else `-- {code}`
	end)
	table.insert(refreshers, update)
	preview.Parent = step2
	UI.label(
		"Texto entre aspas (\"Espada\") vai como texto fixo; sem aspas (price, player.Name) usa a variável do seu código.",
		{ wrap = true, size = 12, color = p.dimText }
	).Parent =
		step2
	step2.Parent = scroller

	local step3 = UI.card(nil, { gap = 8 })
	UI.label("3 · ONDE COLOCAR", { font = Theme.FONT_BOLD, size = 11, color = p.accent, height = 16 }).Parent = step3
	Placement.render(state.placement, step3)
	local insert = UI.button("Inserir código", {
		variant = "primary",
		height = 34,
		onClick = function()
			local registry, err = assistant.register(form)
			if not registry then
				app:toast(err or "Confira os campos.", "warning")
				return
			end
			local insertErr = Placement.insert(app, state.placement, {
				build = function(sdk: string)
					return assistant.build(form, sdk)
				end,
				label = assistant.label(form),
				registry = registry,
				fallbackSdkPath = app.settings:get("sdkPath"),
			})
			if insertErr then
				app:toast(insertErr, "warning")
			end
		end,
	})
	UI.row(8, { insert }, { Size = UDim2.new(1, 0, 0, 36) }).Parent = step3
	UI.label("Tudo vira um passo só no histórico: Ctrl+Z (ou \"Desfazer\") volta o script e o registro.", {
		wrap = true,
		size = 12,
		color = p.dimText,
	}).Parent =
		step3
	step3.Parent = scroller
end

-- Assistants ---------------------------------------------------------------------------------------

local function economy(app: any): Assistant
	return {
		title = "Moeda do jogo",
		intro = "Para cada vez que o jogador <b>ganha</b> ou <b>gasta</b> moedas, gemas etc. Coloque o código logo depois da linha que muda o saldo.",
		fields = function(form, column, refresh)
			form.flow = form.flow or "Sink"
			form.currency = form.currency or "Coins"
			form.reason = form.reason or "Shop"
			form.player = form.player or "player"
			UI.field(
				"O jogador…",
				UI.segmented({
					{ label = "Gastou", value = "Sink" },
					{ label = "Ganhou", value = "Source" },
				}, form.flow, function(value)
					form.flow = value
					refresh()
				end)
			).Parent =
				column
			local currency = textInput(form, "currency", "Coins", refresh)
			UI.field("Qual moeda?", currency, "Nome da moeda (sem espaços): Coins, Gems, Gold…").Parent = column
			local pick = chips(namesOf(app, "economy"), function(name)
				form.currency = name
				currency.Text = name
				refresh()
			end)
			if pick then
				pick.Parent = column
			end
			UI.field("Quanto?", textInput(form, "amount", "price", refresh, true), "Número (50) ou a variável do valor (price).").Parent =
				column
			UI.field(
				"Saldo depois",
				textInput(form, "balance", "0", refresh, true),
				"Variável com o saldo depois da troca (data.Coins). Se não souber, deixe 0."
			).Parent =
				column
			local reasons = {}
			for _, option in Codegen.TRANSACTION_TYPES do
				table.insert(reasons, { label = option.label, value = option.value })
			end
			UI.field(
				"Motivo",
				UI.dropdown({
					options = reasons,
					value = form.reason,
					onChange = function(value)
						form.reason = value
						refresh()
						app:render()
					end,
				})
			).Parent =
				column
			UI.field(
				"Item (opcional)",
				textInput(form, "item", '"Espada"', refresh, true),
				"O que foi comprado. Entre aspas para texto fixo."
			).Parent =
				column
			UI.field("Variável do jogador", textInput(form, "player", "player", refresh, true)).Parent = column
		end,
		build = function(form, sdk)
			return Codegen.economy({
				sdk = sdk,
				player = form.player,
				flow = form.flow,
				currency = Names.sanitize(form.currency or "Coins"),
				amount = form.amount,
				balance = form.balance,
				reason = form.reason,
				item = form.item,
			})
		end,
		register = function(form)
			local name = Names.sanitize(form.currency or "")
			local nameError = Names.eventNameError(name)
			if nameError then
				return nil, `Moeda: {nameError}`
			end
			local registry = Registry.clone(app.registry)
			if not Registry.find(registry, name) then
				local event = Registry.newEvent(name, "economy")
				event.description = "Moeda do jogo"
				local err = Registry.add(registry, event)
				if err then
					return nil, err
				end
			end
			return registry, nil
		end,
		label = function(form)
			return `medir moeda {form.currency}`
		end,
	}
end

local function custom(app: any, state: State): Assistant
	return {
		title = "Ação do jogador",
		intro = "Qualquer coisa que o jogador faz: abriu a loja, derrotou um chefe, entrou no portal. Coloque o código na linha onde isso acontece.",
		fields = function(form, column, refresh)
			form.name = form.name or state.event or ""
			form.player = form.player or "player"
			form.props = form.props or {}
			local name = textInput(form, "name", "BossDerrotado", refresh)
			UI.field("Nome do evento", name, "Letras, números e _ . : - (sem espaços). Aparece assim no painel.").Parent =
				column
			local pick = chips(namesOf(app, "custom"), function(picked)
				form.name = picked
				name.Text = picked
				local event = Registry.find(app.registry, picked)
				if event and #form.props == 0 then
					for _, prop in event.props do
						table.insert(form.props, { key = prop.key, value = "" })
					end
					app:render()
				end
				refresh()
			end)
			if pick then
				pick.Parent = column
			end
			UI.field(
				"Valor (opcional)",
				textInput(form, "value", "1", refresh, true),
				"Um número para somar no painel (dano, tempo, pontos)."
			).Parent =
				column
			local detailList = UI.column(6)
			for index, prop in form.props do
				local key = UI.input({
					text = prop.key,
					placeholder = "chave (boss)",
					onChange = function(text)
						prop.key = text
						refresh()
					end,
				})
				key.Size = UDim2.new(0.4, -4, 0, 28)
				local value = UI.input({
					text = prop.value,
					placeholder = 'valor ("Dragão" ou variável)',
					code = true,
					onChange = function(text)
						prop.value = text
						refresh()
					end,
				})
				value.Size = UDim2.fromScale(0, 0)
				value.AutomaticSize = Enum.AutomaticSize.None
				value.Size = UDim2.fromOffset(0, 28)
				UI.flex().Parent = value
				UI.row(6, {
					key,
					value,
					UI.button("×", {
						variant = "ghost",
						width = 28,
						onClick = function()
							table.remove(form.props, index)
							app:render()
						end,
					}),
				}, { Size = UDim2.new(1, 0, 0, 28) }).Parent =
					detailList
			end
			UI.link("+ adicionar detalhe", function()
				table.insert(form.props, { key = "", value = "" })
				app:render()
			end).Parent =
				detailList
			UI.field(
				"Detalhes (opcional)",
				detailList,
				"Informações extras para filtrar no painel: qual chefe, qual mapa…"
			).Parent =
				column
			UI.field("Variável do jogador", textInput(form, "player", "player", refresh, true)).Parent = column
		end,
		build = function(form, sdk)
			local props = {}
			for _, prop in form.props or {} do
				if prop.key ~= "" then
					table.insert(props, { key = prop.key, value = prop.value })
				end
			end
			return Codegen.custom({
				sdk = sdk,
				player = form.player,
				name = Names.sanitize(form.name or ""),
				value = form.value,
				props = props,
			})
		end,
		register = function(form)
			local name = Names.sanitize(form.name or "")
			local nameError = Names.eventNameError(name)
			if nameError then
				return nil, `Nome do evento: {nameError}`
			end
			local registry = Registry.clone(app.registry)
			local event = Registry.find(registry, name)
			if event and event.kind ~= "custom" then
				return nil, `"{event.name}" já existe como outro tipo de evento.`
			end
			if not event then
				event = Registry.newEvent(name, "custom")
				local err = Registry.add(registry, event :: Registry.EventDef)
				if err then
					return nil, err
				end
			end
			local target = event :: Registry.EventDef
			for _, prop in form.props or {} do
				if prop.key ~= "" then
					if not Names.isValidPropKey(prop.key) then
						return nil, `Detalhe "{prop.key}": use letras, números e _ (começando com letra).`
					end
					local exists = false
					for _, existing in target.props do
						if existing.key == prop.key then
							exists = true
						end
					end
					if not exists then
						table.insert(target.props, { key = prop.key, type = inferType(prop.value or "") })
					end
				end
			end
			return registry, nil
		end,
		label = function(form)
			return `medir {form.name}`
		end,
	}
end

local function funnel(app: any, state: State): Assistant
	return {
		title = "Etapas de um caminho",
		intro = "Um caminho com etapas em ordem (tutorial, primeira compra). O painel mostra em qual etapa os jogadores desistem. Coloque cada etapa onde ela acontece.",
		fields = function(form, column, refresh)
			form.name = form.name or state.event or "Tutorial"
			form.player = form.player or "player"
			if not form.steps then
				local existing = Registry.find(app.registry, form.name)
				form.steps = {}
				if existing and existing.kind == "funnel" then
					for _, step in existing.steps do
						table.insert(form.steps, step.name)
					end
				end
				if #form.steps == 0 then
					form.steps = { "Entrou", "AbriuLoja", "Comprou" }
				end
			end
			form.step = math.clamp(form.step or 1, 1, math.max(1, #form.steps))
			local name = textInput(form, "name", "Tutorial", refresh)
			UI.field("Nome do caminho", name).Parent = column
			local pick = chips(namesOf(app, "funnel"), function(picked)
				form.name = picked
				form.steps = nil
				app:render()
			end)
			if pick then
				pick.Parent = column
			end
			local list = UI.column(6)
			for index, stepName in form.steps do
				local box = UI.input({
					text = stepName,
					placeholder = `Etapa {index}`,
					onChange = function(text)
						form.steps[index] = text
						refresh()
					end,
				})
				box.Size = UDim2.fromOffset(0, 28)
				UI.flex().Parent = box
				UI.row(6, {
					UI.label(`{index}.`, { size = 13, color = UI.palette.dimText, autoX = true, height = 28 }),
					box,
					UI.button("×", {
						variant = "ghost",
						width = 28,
						disabled = #form.steps <= 1,
						onClick = function()
							table.remove(form.steps, index)
							app:render()
						end,
					}),
				}, { Size = UDim2.new(1, 0, 0, 28) }).Parent =
					list
			end
			UI.link("+ adicionar etapa", function()
				table.insert(form.steps, `Etapa{#form.steps + 1}`)
				app:render()
			end).Parent =
				list
			UI.field("Etapas, em ordem", list).Parent = column
			local options = {}
			for index, stepName in form.steps do
				table.insert(options, { label = `{index}. {stepName}`, value = index })
			end
			UI.field(
				"Qual etapa você vai colocar agora?",
				UI.dropdown({
					options = options,
					value = form.step,
					onChange = function(value)
						form.step = value
						refresh()
						app:render()
					end,
				}),
				"Depois de inserir, escolha a próxima etapa e clique na linha onde ela acontece."
			).Parent =
				column
			UI.field("Variável do jogador", textInput(form, "player", "player", refresh, true)).Parent = column
		end,
		build = function(form, sdk)
			local index = form.step or 1
			return Codegen.funnel({
				sdk = sdk,
				player = form.player,
				funnel = Names.sanitize(form.name or ""),
				step = index,
				stepName = (form.steps or {})[index],
			})
		end,
		register = function(form)
			local name = Names.sanitize(form.name or "")
			local nameError = Names.eventNameError(name)
			if nameError then
				return nil, `Nome do caminho: {nameError}`
			end
			local registry = Registry.clone(app.registry)
			local event = Registry.find(registry, name)
			if event and event.kind ~= "funnel" then
				return nil, `"{event.name}" já existe como outro tipo de evento.`
			end
			local steps = {}
			local seen: { [string]: boolean } = {}
			for _, stepName in form.steps or {} do
				local trimmed = string.gsub(string.gsub(stepName, "^%s+", ""), "%s+$", "")
				if trimmed == "" or #trimmed > 64 then
					return nil, "Toda etapa precisa de um nome (até 64 letras)."
				end
				if seen[string.lower(trimmed)] then
					return nil, `Etapa repetida: {trimmed}`
				end
				seen[string.lower(trimmed)] = true
				local previous = nil
				if event then
					for _, step in event.steps do
						if step.name == trimmed then
							previous = step.event
						end
					end
				end
				table.insert(steps, { name = trimmed, event = previous })
			end
			local def = event or Registry.newEvent(name, "funnel")
			def.steps = steps
			local err = Registry.upsert(registry, def)
			if err then
				return nil, err
			end
			return registry, nil
		end,
		label = function(form)
			return `etapa {form.step} de {form.name}`
		end,
	}
end

local function progression(app: any, state: State): Assistant
	return {
		title = "Fases e níveis",
		intro = "Quando o jogador <b>começa</b>, <b>completa</b> ou <b>falha</b> uma fase. O painel mostra onde as pessoas travam.",
		fields = function(form, column, refresh)
			form.path = form.path or state.event or "Fases"
			form.status = form.status or "Complete"
			form.player = form.player or "player"
			local path = textInput(form, "path", "Fases", refresh)
			UI.field("Nome do caminho de fases", path, "Ex.: Fases, Mundo1, Masmorra.").Parent = column
			local pick = chips(namesOf(app, "progression"), function(picked)
				form.path = picked
				path.Text = picked
				refresh()
			end)
			if pick then
				pick.Parent = column
			end
			UI.field(
				"O jogador…",
				UI.segmented({
					{ label = "Começou", value = "Start" },
					{ label = "Completou", value = "Complete" },
					{ label = "Falhou", value = "Fail" },
				}, form.status, function(value)
					form.status = value
					refresh()
				end)
			).Parent =
				column
			UI.field("Qual nível?", textInput(form, "level", "level", refresh, true), "Número (3) ou a variável do nível.").Parent =
				column
			UI.field("Variável do jogador", textInput(form, "player", "player", refresh, true)).Parent = column
		end,
		build = function(form, sdk)
			return Codegen.progression({
				sdk = sdk,
				player = form.player,
				path = Names.sanitize(form.path or ""),
				status = form.status,
				level = form.level,
			})
		end,
		register = function(form)
			local name = Names.sanitize(form.path or "")
			local nameError = Names.eventNameError(name)
			if nameError then
				return nil, `Nome: {nameError}`
			end
			local registry = Registry.clone(app.registry)
			local event = Registry.find(registry, name)
			if event and event.kind ~= "progression" then
				return nil, `"{event.name}" já existe como outro tipo de evento.`
			end
			if not event then
				local err = Registry.add(registry, Registry.newEvent(name, "progression"))
				if err then
					return nil, err
				end
			end
			return registry, nil
		end,
		label = function(form)
			return `medir fase {form.path}`
		end,
	}
end

-- View ---------------------------------------------------------------------------------------------

function View.render(app: any, container: Frame)
	local p = UI.palette
	local state = getState(app)
	local scroller = UI.scroll({ Parent = container }, 12, 16)

	if state.mode == "economy" then
		renderAssistant(app, state, scroller, economy(app))
		return
	elseif state.mode == "custom" then
		renderAssistant(app, state, scroller, custom(app, state))
		return
	elseif state.mode == "funnel" then
		renderAssistant(app, state, scroller, funnel(app, state))
		return
	elseif state.mode == "progression" then
		renderAssistant(app, state, scroller, progression(app, state))
		return
	end

	UI.heading(
		"O que você quer medir?",
		"Escolha uma opção. O plugin escreve o código, mostra antes e coloca no seu script; tudo pode ser desfeito."
	).Parent =
		scroller
	if not Studio.sdkModule() then
		UI.notice("Instale o SDK na aba <b>Início</b> antes: o código gerado usa o módulo RoMetrics.", "warning").Parent =
			scroller
	end

	local function open(mode: Mode)
		state.mode = mode
		state.form = {}
		app:render()
	end

	local options = {
		{
			icon = "R$",
			color = p.success,
			title = "Vendas com Robux",
			description = "Developer products e game passes. Um clique deixa o ProcessReceipt do jogo medido.",
			badge = "SEM CÓDIGO",
			onClick = function()
				app:setTab("sales")
			end,
		},
		{
			icon = "¢",
			color = p.warning,
			title = "Moeda do jogo",
			description = "Moedas ou gemas que o jogador ganha ou gasta (lojas, recompensas).",
			onClick = function()
				open("economy")
			end,
		},
		{
			icon = "★",
			color = p.accent,
			title = "Ação do jogador",
			description = "Abriu a loja, derrotou um chefe, usou um item: qualquer momento importante.",
			onClick = function()
				open("custom")
			end,
		},
		{
			icon = "◆",
			color = Color3.fromHex("#2BB5C9"),
			title = "Toque ou clique em um objeto",
			description = "Portal, botão, prompt ou ferramenta do mapa. Sem código: selecione e marque.",
			badge = "SEM CÓDIGO",
			onClick = function()
				app:setTab("track", "measure")
			end,
		},
		{
			icon = "≡",
			color = Theme.kindColor("funnel"),
			title = "Etapas de um caminho",
			description = "Tutorial, primeira compra: veja em qual etapa os jogadores desistem.",
			onClick = function()
				open("funnel")
			end,
		},
		{
			icon = "▲",
			color = Theme.kindColor("progression"),
			title = "Fases e níveis",
			description = "Começou, completou ou falhou uma fase.",
			onClick = function()
				open("progression")
			end,
		},
	}
	for _, option in options do
		UI.choice(option :: any).Parent = scroller
	end
end

return View

--!strict
-- "Snippets": ready-made code using registry events, inserted into a selected or new Script.
local Registry = require(script.Parent.Parent.Registry)
local Snippets = require(script.Parent.Parent.Snippets)
local Studio = require(script.Parent.Parent.Studio)
local Theme = require(script.Parent.Parent.Theme)
local UI = require(script.Parent.Parent.UI)

type State = { id: string, event: string? }

local function getState(app: any): State
	local state = app.state.snippets
	if not state then
		state = { id = "setup", event = nil }
		app.state.snippets = state
	end
	return state
end

local View = {
	id = "snippets",
	title = "Código",
	watches = { selection = true },
}

function View.render(app: any, container: Frame)
	local state = getState(app)
	local p = UI.palette
	local left, main = app:split(container, 200)

	local list = UI.scroll({ Parent = left }, 2, 8)
	for _, snippet in Snippets.list do
		UI.listRow(snippet.title, {
			selected = snippet.id == state.id,
			onClick = function()
				state.id = snippet.id
				if snippet.kind then
					local event = if state.event then Registry.find(app.registry, state.event) else nil
					if not event or event.kind ~= snippet.kind then
						local candidates = Registry.byKind(app.registry, snippet.kind)
						state.event = if candidates[1] then candidates[1].name else nil
					end
				end
				app:render()
			end,
		}).Parent =
			list
	end

	local snippet = Snippets.get(state.id) or Snippets.list[1]
	local settings = app.settings:values()
	local event: Registry.EventDef? = nil
	if snippet.kind and state.event then
		local found = Registry.find(app.registry, state.event)
		if found and found.kind == snippet.kind then
			event = found
		end
	end
	local output = snippet.build({
		sdkPath = settings.sdkPath,
		secretName = settings.secretName,
		endpoint = settings.endpoint,
		event = event,
	})

	local scroller = UI.scroll({ Parent = main }, 10, 12)
	UI.label(snippet.title, { font = Theme.FONT_BOLD, size = 18 }).Parent = scroller
	UI.label(snippet.description, { wrap = true, color = p.subText }).Parent = scroller
	if not Studio.sdkModule() then
		UI.notice("O SDK ainda não está neste place: este código vai falhar no require. Instale na aba <b>Início</b>.", "warning").Parent =
			scroller
		UI.button("Ir para Início", {
			onClick = function()
				app:setTab("home")
			end,
		}).Parent =
			scroller
	end

	local controlsPanel, controls = UI.section("Opções")
	if snippet.kind then
		local options = {}
		for _, candidate in Registry.byKind(app.registry, snippet.kind) do
			table.insert(options, { label = candidate.name, value = candidate.name })
		end
		UI.controlRow(
			"Evento",
			UI.dropdown({
				options = options,
				value = if event then event.name else nil,
				placeholder = if #options == 0 then `Nenhum evento {snippet.kind} no registro` else "Escolher…",
				onChange = function(value)
					state.event = value
					app:render()
				end,
			}),
			if event then nil else "Sem evento: o código usa um nome de exemplo."
		).Parent =
			controls
	end
	UI.controlRow(
		"SDK",
		UI.label(settings.sdkPath, { font = Theme.FONT_CODE, size = 13, color = p.subText }),
		"Altere na aba Config."
	).Parent =
		controls
	if snippet.id == "setup" then
		UI.controlRow("Secret", UI.label(settings.secretName, { font = Theme.FONT_CODE, size = 13, color = p.subText })).Parent =
			controls
	end
	controlsPanel.Parent = scroller

	local code = UI.input({ text = Snippets.render(output), multiline = true, code = true, readOnly = true })
	code.TextWrapped = false
	code.Parent = scroller

	-- Where the code goes: the selected script, else the setup script, else a new Script.
	local selected = Studio.selectedScript()
	local setup = if snippet.id == "setup" then nil else Studio.setupScript()
	local target = selected or setup
	local function insert(into: LuaSourceContainer?)
		local result, err = Studio.insertSnippet(output, into, snippet.scriptName)
		if err or not result then
			app:toast(`Falha: {err}`, "error")
			return
		end
		Studio.select({ result })
		app:toast(
			if into then `Inserido em {result:GetFullName()} (Ctrl+Z desfaz)` else `Criado {result:GetFullName()}`,
			"success"
		)
		Studio.openScript(app.plugin, result)
	end
	local actions: { Instance } = {}
	if target then
		table.insert(
			actions,
			UI.button(`Inserir em {target.Name}`, {
				variant = "primary",
				onClick = function()
					insert(target)
				end,
			})
		)
	end
	table.insert(
		actions,
		UI.button(`Criar Script {snippet.scriptName}`, {
			variant = if target then "secondary" else "primary",
			onClick = function()
				insert(nil)
			end,
		})
	)
	UI.notice(
		if selected
			then `Vai inserir no script selecionado: <b>{selected:GetFullName()}</b>.`
			elseif setup then `Nenhum script selecionado: vai inserir no script de setup <b>{setup.Name}</b>. Selecione outro no Explorer para trocar.`
			else "Selecione um script no Explorer para inserir nele, ou crie um novo em ServerScriptService.",
		"info"
	).Parent =
		scroller
	UI.row(8, actions).Parent = scroller
	UI.label(
		"As linhas de require/GetService que faltam vão para o topo e o código vai para o fim do script. "
			.. "Scripts novos vão para ServerScriptService (o SDK só roda no servidor).",
		{ wrap = true, color = p.dimText, size = Theme.SMALL_SIZE }
	).Parent =
		scroller
end

return View

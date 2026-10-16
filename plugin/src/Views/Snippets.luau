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
	title = "Snippets",
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

	local controlsPanel, controls = UI.section("Controls")
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

	local target = Studio.selectedScript()
	local actions: { Instance } = {
		UI.button(if target then `Inserir em {target.Name}` else "Selecione um script para inserir", {
			variant = if target then "primary" else "secondary",
			disabled = target == nil,
			onClick = function()
				if not target then
					return
				end
				local result, err = Studio.insertSnippet(output, target, snippet.scriptName)
				if err or not result then
					app:toast(`Falha: {err}`, "error")
					return
				end
				app:toast(`Inserido em {result:GetFullName()} (Ctrl+Z desfaz)`, "success")
				Studio.openScript(app.plugin, result)
			end,
		}),
		UI.button(`Novo Script ({snippet.scriptName})`, {
			onClick = function()
				local result, err = Studio.insertSnippet(output, nil, snippet.scriptName)
				if err or not result then
					app:toast(`Falha: {err}`, "error")
					return
				end
				Studio.select({ result })
				app:toast(`Criado {result:GetFullName()}`, "success")
				Studio.openScript(app.plugin, result)
			end,
		}),
	}
	UI.row(8, actions).Parent = scroller
	UI.label(
		"Inserir: as linhas de require/GetService que faltam vão para o topo; o corpo vai para o fim do script. "
			.. "Scripts novos vão para ServerScriptService (o SDK só roda no servidor).",
		{ wrap = true, color = p.dimText, size = Theme.SMALL_SIZE }
	).Parent =
		scroller
end

return View

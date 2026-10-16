--!strict
-- "Início": setup checklist. Each step shows whether it is done in this place and the one action
-- that finishes it (install the SDK from GitHub, create the setup script, ...).
local Installer = require(script.Parent.Parent.Installer)
local Snippets = require(script.Parent.Parent.Snippets)
local Studio = require(script.Parent.Parent.Studio)
local Tagging = require(script.Parent.Parent.Tagging)
local Theme = require(script.Parent.Parent.Theme)
local UI = require(script.Parent.Parent.UI)

local View = {
	id = "home",
	title = "Início",
	watches = {},
}

local DEFAULT_ENDPOINT = "https://ingest.rometrics.app"

-- Not stored in the place: the plugin cannot read Secrets, so the user confirms it once per place.
local function secretKey(): string
	return `RoMetrics_secretOk_{game.PlaceId}`
end

local function pathOf(instance: Instance): string
	local parts = {}
	local node: Instance? = instance
	while node and node ~= game do
		table.insert(parts, 1, node.Name)
		node = node.Parent
	end
	return table.concat(parts, ".")
end

function View.render(app: any, container: Frame)
	local p = UI.palette
	local settings = app.settings
	app.state.home = app.state.home or { busy = false, progress = "" }
	local state = app.state.home

	local sdk = Studio.sdkModule()
	local setupScript = Studio.setupScript()
	local endpoint: string = settings:get("endpoint")
	local endpointSet = endpoint ~= "" and endpoint ~= DEFAULT_ENDPOINT
	local secretOk = app.plugin:GetSetting(secretKey()) == true
	local hasEvent = #app.registry.events > 0

	local doneCount = 0
	for _, done in { sdk ~= nil, endpointSet, secretOk, setupScript ~= nil, hasEvent } do
		if done then
			doneCount += 1
		end
	end

	local scroller = UI.scroll({ Parent = container }, 10, 14)

	UI.column(2, {
		UI.label("Configure o RoMetrics neste jogo", { font = Theme.FONT_BOLD, size = 18, height = 26 }),
		UI.label(
			`{doneCount} de 5 passos concluídos. Depois disso é só dar Play e ver os dados chegando no dashboard.`,
			{ wrap = true, color = p.subText, size = 13 }
		),
	}).Parent =
		scroller

	-- 1. SDK
	local progress = UI.label(state.progress, { size = Theme.SMALL_SIZE, color = p.subText, wrap = true })
	local function install()
		if state.busy then
			return
		end
		state.busy = true
		state.progress = "Começando…"
		app:render()
		task.spawn(function()
			local result, err = Installer.install(sdk, Tagging.record, function(message)
				state.progress = message
				if progress.Parent then
					progress.Text = message
				end
			end)
			state.busy = false
			if result then
				settings:set("sdkPath", pathOf(result.module))
				state.progress = ""
				app:toast(
					`SDK {result.version} {if result.updated then "atualizado" else "instalado"} ({result.files} arquivos). Ctrl+Z desfaz.`,
					"success"
				)
				Studio.select({ result.module })
			else
				state.progress = `Erro: {err}. Se o Studio pediu permissão de HTTP, aceite e tente de novo.`
				app:toast("Não foi possível instalar o SDK", "error")
			end
			app:render()
		end)
	end
	local version = if sdk then sdk:GetAttribute(Installer.VERSION_ATTRIBUTE) else nil
	UI.step({
		number = 1,
		title = "Instalar o SDK",
		description = if sdk
			then `Instalado em {pathOf(sdk)}.`
			else "Baixa o módulo RoMetrics do GitHub e coloca em ReplicatedStorage. Um clique, sem arquivo para baixar.",
		state = if sdk then "done" else "todo",
		status = if sdk then (if type(version) == "string" then version else "instalado") else nil,
		extra = if state.progress ~= "" then { progress } else nil,
		actions = {
			UI.button(if state.busy then "Instalando…" elseif sdk then "Atualizar do GitHub" else "Instalar do GitHub", {
				variant = if sdk then "secondary" else "primary",
				disabled = state.busy,
				onClick = install,
			}),
			if sdk
				then UI.button("Mostrar no Explorer", {
					variant = "ghost",
					onClick = function()
						Studio.select({ sdk })
					end,
				})
				else nil,
		},
	}).Parent =
		scroller

	-- 2. Endpoint
	local testResult = UI.label("", { size = Theme.SMALL_SIZE, color = p.subText, wrap = true })
	testResult.Visible = false
	local endpointBox = UI.input({
		text = endpoint,
		placeholder = "https://seu-servidor.exemplo.com",
		onCommit = function(text)
			local value = string.gsub(string.gsub(text, "%s", ""), "/+$", "")
			settings:set("endpoint", if value == "" then DEFAULT_ENDPOINT else value)
			app:render()
		end,
	})
	UI.step({
		number = 2,
		title = "Endereço do servidor",
		description = "Para onde o jogo envia os eventos: o mesmo endereço do seu dashboard RoMetrics (https://…).",
		state = if endpointSet then "done" else "todo",
		extra = { endpointBox, testResult },
		actions = {
			UI.button("Testar conexão", {
				onClick = function()
					testResult.Visible = true
					testResult.Text = "Testando…"
					testResult.TextColor3 = p.subText
					task.spawn(function()
						local ok, message = Studio.testConnection(settings:get("endpoint"))
						if testResult.Parent then
							testResult.Text = message
							testResult.TextColor3 = if ok then p.success else p.danger
						end
					end)
				end,
			}),
		},
	}).Parent =
		scroller

	-- 3. Secret
	local secretName: string = settings:get("secretName")
	UI.step({
		number = 3,
		title = "Guardar a chave no Secret",
		description = `Gere a chave de ingestão no dashboard e salve como Secret com o nome "{secretName}":`,
		state = if secretOk then "done" else "todo",
		status = if secretOk then "confirmado" else nil,
		extra = {
			UI.notice(
				"<b>Servidores ao vivo:</b> Creator Hub › sua experiência › Secrets.\n"
					.. "<b>Play no Studio:</b> File › Experience Settings › Security › Local Secrets.\n"
					.. "O plugin nunca lê a chave: ela fica só no Roblox.",
				"info"
			),
		},
		actions = {
			UI.button(if secretOk then "Desmarcar" else "Já criei o Secret", {
				variant = if secretOk then "ghost" else "secondary",
				onClick = function()
					app.plugin:SetSetting(secretKey(), not secretOk)
					app:render()
				end,
			}),
		},
	}).Parent =
		scroller

	-- 4. Setup script
	UI.step({
		number = 4,
		title = "Script de inicialização",
		description = if setupScript
			then `Encontrado em {pathOf(setupScript)}.`
			else "Cria ServerScriptService.RoMetricsSetup com RoMetrics.init, a chave do Secret e o registro de compras.",
		state = if setupScript then "done" elseif sdk then "todo" else "optional",
		actions = {
			if setupScript
				then UI.button("Abrir script", {
					onClick = function()
						Studio.openScript(app.plugin, setupScript)
					end,
				})
				else UI.button("Criar script de setup", {
					variant = if sdk then "primary" else "secondary",
					onClick = function()
						local values = settings:values()
						local snippet = Snippets.get("setup")
						if not snippet then
							return
						end
						local output = snippet.build({
							sdkPath = values.sdkPath,
							secretName = values.secretName,
							endpoint = values.endpoint,
							event = nil,
						})
						local created, err = Studio.insertSnippet(output, nil, snippet.scriptName)
						if err or not created then
							app:toast(`Falha: {err}`, "error")
							return
						end
						app:toast(`Criado {created:GetFullName()} (Ctrl+Z desfaz)`, "success")
						Studio.openScript(app.plugin, created)
						app:render()
					end,
				}),
		},
	}).Parent =
		scroller

	-- 5. Events
	UI.step({
		number = 5,
		title = "Registrar eventos",
		description = if hasEvent
			then `{#app.registry.events} evento(s) no registro. Use a aba Código para colar o envio nos seus scripts.`
			else "Crie eventos (ex.: LojaAberta, BossDerrotado) e marque objetos do mapa para enviar sem código.",
		state = if hasEvent then "done" else "todo",
		actions = {
			UI.button(if hasEvent then "Ver eventos" else "Criar evento", {
				variant = if hasEvent then "secondary" else "primary",
				onClick = function()
					app:setTab("events")
				end,
			}),
			UI.button("Código pronto", {
				variant = "ghost",
				onClick = function()
					app:setTab("snippets")
				end,
			}),
		},
	}).Parent =
		scroller

	UI.notice(
		"Pronto? Dê <b>Play</b> e confira na aba <b>Validação</b> e no dashboard se os eventos chegaram.",
		if doneCount == 5 then "success" else "info"
	).Parent =
		scroller
end

return View

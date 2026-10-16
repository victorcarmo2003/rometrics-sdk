--!strict
-- "Ajustes": server address, the Secret with the key, the connection test with the dashboard, SDK
-- update and the advanced tools (validation, funnels, highlight).
local Home = require(script.Parent.Home)
local Installer = require(script.Parent.Parent.Installer)
local Registry = require(script.Parent.Parent.Registry)
local Studio = require(script.Parent.Parent.Studio)
local Tagging = require(script.Parent.Parent.Tagging)
local Theme = require(script.Parent.Parent.Theme)
local UI = require(script.Parent.Parent.UI)

local View = {
	id = "config",
	title = "Ajustes",
	nav = true,
	watches = {},
}

local DEFAULT_ENDPOINT = "https://ingest.rometrics.app"
local PLUGIN_VERSION = "0.3.0"
View.PLUGIN_VERSION = PLUGIN_VERSION

local function sectionTitle(text: string): any
	return UI.label(text, { font = Theme.FONT_BOLD, size = 11, color = UI.palette.dimText, height = 18 })
end

function View.render(app: any, container: Frame)
	local p = UI.palette
	local settings = app.settings
	app.state.config = app.state.config or { code = "", testing = false, testResult = nil, updating = false, sending = false, sendResult = nil }
	local state = app.state.config
	local scroller = UI.scroll({ Parent = container }, 12, 16)

	UI.heading("Ajustes", "Para onde o jogo manda os dados e como ele se identifica.").Parent = scroller

	-- Connection ----------------------------------------------------------------------------------
	sectionTitle("CONEXÃO").Parent = scroller
	local connection = UI.card(nil, { gap = 12 })

	local pingResult = UI.label("", { size = 12, color = p.subText, wrap = true })
	pingResult.Visible = false
	UI.field(
		"1. Endereço do servidor",
		UI.input({
			text = settings:get("endpoint"),
			placeholder = DEFAULT_ENDPOINT,
			onCommit = function(text)
				local value = string.gsub(string.gsub(text, "%s", ""), "/+$", "")
				settings:set("endpoint", if value == "" then DEFAULT_ENDPOINT else value)
			end,
		}),
		"O mesmo endereço do seu painel RoMetrics (https://…). Vai no script de início."
	).Parent =
		connection
	UI.row(8, {
		UI.button("Testar endereço", {
			onClick = function()
				pingResult.Visible = true
				pingResult.Text = "Testando…"
				pingResult.TextColor3 = p.subText
				task.spawn(function()
					local ok, message = Studio.testConnection(settings:get("endpoint"))
					if pingResult.Parent then
						pingResult.Text = message
						pingResult.TextColor3 = if ok then p.success else p.danger
					end
				end)
			end,
		}),
	}).Parent =
		connection
	pingResult.Parent = connection

	local secretName: string = settings:get("secretName")
	local secretOk = app.plugin:GetSetting(Home.secretKey()) == true
	UI.field(
		"2. Chave no Secret",
		UI.notice(
			`Gere a chave no painel (Configurações › Chaves) e salve como Secret com o nome <b>{secretName}</b>:\n`
				.. "• <b>Servidores ao vivo:</b> Creator Hub › sua experiência › Secrets.\n"
				.. "• <b>Play no Studio:</b> File › Experience Settings › Security › Local Secrets.\n"
				.. "O plugin nunca lê a chave: ela fica só no Roblox.",
			"info"
		)
	).Parent =
		connection
	UI.row(10, {
		UI.toggle(secretOk, function(value)
			app.plugin:SetSetting(Home.secretKey(), value)
		end),
		UI.label("Já criei o Secret neste jogo", { size = 13, autoX = true }),
	}).Parent =
		connection

	local codeBox = UI.input({
		text = state.code,
		placeholder = "Código do site (ex.: K7M-Q2P)",
		onChange = function(text)
			state.code = text
		end,
	})
	codeBox.Size = UDim2.fromOffset(0, 28)
	UI.flex().Parent = codeBox
	local result = state.testResult
	UI.field(
		"3. Testar com o site",
		UI.row(8, {
			codeBox,
			UI.button(if state.testing then "Testando…" else "Testar", {
				variant = "primary",
				disabled = state.testing,
				onClick = function()
					if state.testing then
						return
					end
					state.testing = true
					state.testResult = nil
					app:render()
					task.spawn(function()
						local endpoint = settings:get("endpoint")
						local ok, message, gameName, matches, lastEventAt = Studio.reportConnectionTest(
							endpoint,
							state.code,
							Studio.placeReport(endpoint, PLUGIN_VERSION)
						)
						state.testing = false
						if ok then
							-- Kept so "Início" can keep asking the server whether events arrive.
							app:setTestCode(state.code)
							app.events = {
								at = os.time(),
								ok = true,
								message = "ok",
								gameName = gameName,
								matches = matches,
								lastEventAt = lastEventAt,
							}
						end
						if ok and matches then
							state.testResult = {
								kind = "success",
								message = `Conectado a <b>{gameName}</b>. Dê <b>Play</b>: a aba Início mostra quando os eventos chegarem.`,
							}
						elseif ok then
							state.testResult = {
								kind = "warning",
								message = `O código é do jogo <b>{gameName}</b>, mas este place é outro (GameId {game.GameId}).`,
							}
						else
							state.testResult = { kind = "danger", message = `Falhou: {message}` }
						end
						app:render()
					end)
				end,
			}),
		}, { Size = UDim2.new(1, 0, 0, 30) }),
		"No site: Configurações › Jogos › Testar conexão. Copie o código e cole aqui."
	).Parent =
		connection
	if result then
		UI.notice(result.message, result.kind).Parent = connection
	end

	-- Custom events from the registry (or a sample), queued by the server as if the SDK sent them.
	local testNames = {}
	for _, event in app.registry.events do
		if event.kind == "custom" then
			table.insert(testNames, event.name)
		end
	end
	if #testNames == 0 then
		testNames = { "RoMetricsTest" }
	end
	UI.field(
		"4. Enviar eventos de teste",
		UI.row(8, {
			UI.button(if state.sending then "Enviando…" else `Enviar {math.min(#testNames, 10)} evento(s)`, {
				disabled = state.sending,
				onClick = function()
					if state.sending then
						return
					end
					local code = if state.code ~= "" then state.code else app:testCode()
					state.sending = true
					state.sendResult = nil
					app:render()
					task.spawn(function()
						local ok, message = Studio.sendTestEvents(settings:get("endpoint"), code or "", testNames)
						state.sending = false
						state.sendResult = {
							kind = if ok then "success" else "danger",
							message = if ok
								then `{message}: {table.concat(testNames, ", ", 1, math.min(#testNames, 10))}. Veja na aba Eventos do painel (marcados como teste).`
								else `Falhou: {message}`,
						}
						app:render()
					end)
				end,
			}),
		}, { Size = UDim2.new(1, 0, 0, 30) }),
		"Manda os eventos custom do registro uma vez cada (valor 1), sem precisar dar Play. Usa o código acima."
	).Parent =
		connection
	if state.sendResult then
		UI.notice(state.sendResult.message, state.sendResult.kind).Parent = connection
	end
	connection.Parent = scroller

	-- SDK -------------------------------------------------------------------------------------------
	sectionTitle("SDK").Parent = scroller
	local sdk = Studio.sdkModule()
	local version = if sdk then sdk:GetAttribute(Installer.VERSION_ATTRIBUTE) else nil
	local sdkCard = UI.card(nil, { gap = 8 })
	UI.statusRow({
		state = if sdk then "ok" else "todo",
		title = if sdk then "Instalado" else "Não instalado",
		detail = if sdk
			then `{Studio.dottedPath(sdk)}{if type(version) == "string" then ` · {version}` else ""}`
			else "Instale pela aba Início.",
		actions = if sdk and sdk:FindFirstChild("Tags")
			then {
				UI.button(if state.updating then "Atualizando…" else "Atualizar", {
					variant = "secondary",
					disabled = state.updating,
					onClick = function()
						state.updating = true
						app:render()
						task.spawn(function()
							local done, err = Installer.install(sdk, Tagging.record)
							state.updating = false
							if done then
								app:toast(`SDK atualizado para {done.version}.`, "success", {
									text = "Desfazer",
									onClick = function()
										app:undo()
									end,
								})
							else
								app:toast(`Não deu para atualizar: {err}`, "error")
							end
							app:render()
						end)
					end,
				}),
			}
			else nil,
	}).Parent =
		sdkCard
	if sdk and not sdk:FindFirstChild("Tags") then
		UI.label("Instalado como pacote (Wally): atualize pelo seu wally.toml.", { size = 12, color = p.dimText, wrap = true }).Parent =
			sdkCard
	end
	sdkCard.Parent = scroller

	-- Advanced --------------------------------------------------------------------------------------
	sectionTitle("AVANÇADO").Parent = scroller
	local advanced = UI.card(nil, { gap = 4, padding = 10 })
	UI.statusRow({
		state = "off",
		title = "Conferir problemas",
		detail = "Nomes inválidos, eventos usados mas não registrados, objetos marcados sem gatilho.",
		actions = {
			UI.button("Abrir", {
				variant = "ghost",
				onClick = function()
					app.state.validate = nil
					app:setTab("validate", "config")
				end,
			}),
		},
	}).Parent =
		advanced
	UI.statusRow({
		state = "off",
		title = "Editor de funis",
		detail = "Reordenar etapas e ligar eventos a cada etapa, com diagrama.",
		actions = {
			UI.button("Abrir", {
				variant = "ghost",
				onClick = function()
					app:setTab("flows", "config")
				end,
			}),
		},
	}).Parent =
		advanced
	UI.statusRow({
		state = "off",
		title = "Destacar objetos marcados",
		detail = "Contorno azul no mapa em tudo que tem a tag RoMetrics.",
		actions = {
			UI.toggle(settings:get("highlight"), function(value)
				settings:set("highlight", value)
				app.highlighter:setEnabled(value)
			end),
		},
	}).Parent =
		advanced
	advanced.Parent = scroller

	local dash = UI.input({
		text = settings:get("dashboardUrl"),
		onCommit = function(text)
			if text ~= "" then
				settings:set("dashboardUrl", text)
			end
		end,
	})
	UI.field("Endereço do painel (para copiar)", dash, "Plugins não abrem o navegador: selecione e copie (Ctrl+C).").Parent =
		scroller

	UI.label(
		`Plugin {PLUGIN_VERSION} · registro {Registry.MODULE_NAME}: {#app.registry.events} evento(s) · {#Tagging.tagged()} objeto(s) marcados. Preferências ficam no seu Studio, não no place.`,
		{ wrap = true, color = p.dimText, size = 12 }
	).Parent =
		scroller
end

return View

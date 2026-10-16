--!strict
-- "Início": what is ready in this place (live), the one action that fixes what is not, and the
-- way into "o que você quer medir?".
local Installer = require(script.Parent.Parent.Installer)
local Lint = require(script.Parent.Parent.Lint)
local Snippets = require(script.Parent.Parent.Snippets)
local Studio = require(script.Parent.Parent.Studio)
local Tagging = require(script.Parent.Parent.Tagging)
local Theme = require(script.Parent.Parent.Theme)
local UI = require(script.Parent.Parent.UI)

local View = {
	id = "home",
	title = "Início",
	nav = true,
	watches = { events = true },
}

-- Not stored in the place: the plugin cannot read Secrets, so the user confirms it once per place.
function View.secretKey(): string
	return `RoMetrics_secretOk_{game.PlaceId}`
end

local function ago(seconds: number): string
	if seconds < 60 then
		return "há poucos segundos"
	elseif seconds < 3600 then
		return `há {math.floor(seconds / 60)} min`
	end
	return `há {math.floor(seconds / 3600)} h`
end

function View.render(app: any, container: Frame)
	local p = UI.palette
	local settings = app.settings
	app.state.home = app.state.home or { busy = false, progress = "" }
	local state = app.state.home

	local sdk = Studio.sdkModule()
	local setupScript = Studio.setupScript()
	local endpoint: string = settings:get("endpoint")
	-- The plugin cannot read Secrets: "connected" is the user's confirmation in Ajustes.
	local connected = app.plugin:GetSetting(View.secretKey()) == true
	local owners = Studio.receiptOwners()
	local unwrapped = 0
	for _, owner in owners do
		if not owner.assignment.wrapped and not owner.assignment.tracked then
			unwrapped += 1
		end
	end
	local salesOk = #owners > 0 and unwrapped == 0 and #owners == 1

	local done = 0
	for _, ok in { sdk ~= nil, setupScript ~= nil, connected, #owners == 0 or salesOk } do
		if ok then
			done += 1
		end
	end

	local scroller = UI.scroll({ Parent = container }, 12, 16)

	-- Hero
	local hero = UI.card({
		UI.label(
			if done == 4 then "Tudo pronto. Dê Play e veja os dados chegando." else "Vamos deixar seu jogo pronto para medir",
			{ font = Theme.FONT_BOLD, size = 18, height = 24, wrap = true }
		),
		UI.label(
			if done == 4
				then "O RoMetrics já está ligado neste jogo. Agora escolha o que quer acompanhar."
				else `{done} de 4 itens prontos. Cada item abaixo tem um botão que resolve.`,
			{ wrap = true, size = 13, color = p.subText }
		),
		UI.progress(done / 4, if done == 4 then p.success else p.accent),
	}, { gap = 8, padding = 16, stroke = p.accent:Lerp(p.border, 0.6) })
	hero.Parent = scroller

	-- Checklist
	local checklist = UI.card(nil, { gap = 2, padding = 10 })
	UI.label("NESTE JOGO", { font = Theme.FONT_BOLD, size = 11, color = p.dimText, height = 18 }).Parent = checklist

	-- 1. SDK
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
			end)
			state.busy = false
			state.progress = ""
			if result then
				settings:set("sdkPath", Studio.dottedPath(result.module))
				app:toast(
					`SDK {result.version} {if result.updated then "atualizado" else "instalado"}.`,
					"success",
					{ text = "Desfazer", onClick = function()
						app:undo()
					end }
				)
			else
				app:toast(`Não deu para instalar: {err}. Se o Studio pediu permissão de HTTP, aceite e tente de novo.`, "error")
			end
			app:render()
		end)
	end
	local version = if sdk then sdk:GetAttribute(Installer.VERSION_ATTRIBUTE) else nil
	UI.statusRow({
		state = if state.busy then "busy" elseif sdk then "ok" else "todo",
		title = "SDK do RoMetrics",
		detail = if state.busy
			then state.progress
			elseif sdk then `Instalado{if type(version) == "string" then ` ({version})` else ""} em {Studio.dottedPath(sdk)}`
			else "O módulo que envia os dados. Um clique baixa e instala.",
		actions = if sdk
			then nil
			else { UI.button(if state.busy then "Instalando…" else "Instalar", { variant = "primary", disabled = state.busy, onClick = install }) },
	}).Parent =
		checklist

	-- 2. Setup script
	UI.statusRow({
		state = if setupScript then "ok" elseif sdk then "todo" else "off",
		title = "Script de início",
		detail = if setupScript
			then `RoMetrics.init em {Studio.dottedPath(setupScript)}`
			else "Liga o RoMetrics quando o servidor abre (RoMetrics.init).",
		actions = {
			if setupScript
				then UI.button("Abrir", {
					variant = "ghost",
					onClick = function()
						Studio.openScript(app.plugin, setupScript)
					end,
				})
				else UI.button("Criar", {
					variant = if sdk then "primary" else "secondary",
					disabled = sdk == nil,
					onClick = function()
						local values = settings:values()
						local snippet = Snippets.get("setup")
						if not snippet then
							return
						end
						local output = snippet.build({
							sdkPath = Studio.detectSdkPath() or values.sdkPath,
							secretName = values.secretName,
							endpoint = values.endpoint,
							event = nil,
						})
						local created, err = Studio.insertSnippet(output, nil, snippet.scriptName)
						if err or not created then
							app:toast(`Não deu para criar: {err}`, "error")
							return
						end
						app:toast(`Criado {created:GetFullName()}.`, "success", {
							text = "Desfazer",
							onClick = function()
								app:undo()
							end,
						})
						Studio.openScript(app.plugin, created)
						app:render()
					end,
				}),
		},
	}).Parent =
		checklist

	-- 3. Connection
	UI.statusRow({
		state = if connected then "ok" else "todo",
		title = "Conexão com o painel",
		detail = if connected
			then `Enviando para {endpoint}`
			else "Endereço do servidor e chave (Secret). Leva 2 minutos.",
		actions = {
			UI.button(if connected then "Ajustar" else "Conectar", {
				variant = if connected then "ghost" else "primary",
				onClick = function()
					app:setTab("config")
				end,
			}),
		},
	}).Parent =
		checklist

	-- 4. Sales
	local salesDetail: string
	local salesState: UI.StatusState
	if #owners == 0 then
		salesState = "off"
		salesDetail = "Nenhum script define ProcessReceipt. Game passes já são medidos sozinhos."
	elseif #owners > 1 then
		salesState = "error"
		salesDetail = `{#owners} scripts definem ProcessReceipt: só o último vale.`
	elseif unwrapped > 0 then
		salesState = "warn"
		salesDetail = `Vendas de Robux em {owners[1].script.Name} ainda não são medidas.`
	else
		salesState = "ok"
		salesDetail = `Medidas em {owners[1].script.Name} (linha {owners[1].assignment.line}). Game passes: automático.`
	end
	UI.statusRow({
		state = salesState,
		title = "Vendas com Robux",
		detail = salesDetail,
		actions = {
			UI.button(if salesState == "warn" or salesState == "error" then "Resolver" else "Ver", {
				variant = if salesState == "warn" or salesState == "error" then "primary" else "ghost",
				onClick = function()
					app:setTab("sales")
				end,
			}),
		},
	}).Parent =
		checklist

	-- 5. Events arriving (asked to the server with the connection-test code saved in Ajustes)
	local events = app.events
	local code = app:testCode()
	local eventsState: UI.StatusState = "off"
	local eventsDetail: string
	local eventsActions: { any } = {}
	if events and not events.ok then
		eventsState = "warn"
		eventsDetail = `O servidor não respondeu: {UI.escape(events.message)}`
	elseif events and events.lastEventAt then
		local age = math.max(0, os.time() - events.lastEventAt)
		eventsState = if age < 120 then "busy" else "ok"
		eventsDetail = if age < 120
			then `<b>Chegando!</b> Último evento {ago(age)} em {UI.escape(events.gameName or "seu jogo")}.`
			else `Último evento {ago(age)}. Dê <b>Play</b> para mandar mais.`
	elseif events then
		eventsState = "todo"
		eventsDetail = `Conectado a {UI.escape(events.gameName or "seu jogo")}, mas nenhum evento chegou ainda. Dê <b>Play</b> e espere ~10 s.`
	elseif code then
		eventsState = "todo"
		eventsDetail = "Perguntando ao servidor…"
	else
		eventsDetail = "Para acompanhar aqui: Ajustes › Testar com o site (código de 6 letras). Depois é só dar Play."
		table.insert(
			eventsActions,
			UI.button("Ajustes", {
				variant = "ghost",
				onClick = function()
					app:setTab("config")
				end,
			})
		)
	end
	if code then
		table.insert(
			eventsActions,
			UI.button(if app.checking then "…" else "Atualizar", {
				variant = "ghost",
				onClick = function()
					task.spawn(function()
						app:checkEvents()
						app:render()
					end)
				end,
			})
		)
	end
	UI.statusRow({ state = eventsState, title = "Eventos chegando", detail = eventsDetail, actions = eventsActions }).Parent =
		checklist
	checklist.Parent = scroller

	-- What next
	UI.label("PRÓXIMO PASSO", { font = Theme.FONT_BOLD, size = 11, color = p.dimText, height = 18 }).Parent = scroller
	UI.choice({
		icon = "+",
		color = p.accent,
		title = "O que você quer medir?",
		description = "Vendas, moedas, ações dos jogadores, etapas e fases. O plugin escreve o código e coloca no lugar certo.",
		onClick = function()
			app.state.measure = nil
			app:setTab("measure")
		end,
	}).Parent =
		scroller

	-- Problems (only when there are any)
	local issues = Lint.run(app.registry, Studio.taggedInfo(), app:usages())
	local counts = Lint.counts(issues)
	if counts.error + counts.warning > 0 then
		UI.choice({
			icon = "!",
			color = if counts.error > 0 then p.danger else p.warning,
			title = `{counts.error + counts.warning} coisa(s) para conferir`,
			description = "Nomes inválidos, eventos usados no código mas não registrados, objetos marcados sem gatilho…",
			onClick = function()
				app.state.validate = nil
				app:setTab("validate", "home")
			end,
		}).Parent =
			scroller
	end
end

return View

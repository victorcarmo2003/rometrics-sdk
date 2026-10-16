--!strict
-- "Vendas": finds who assigns MarketplaceService.ProcessReceipt in this place and wraps it with
-- RoMetrics.wrapProcessReceipt in one click (diff preview, undo). Never adds a second
-- ProcessReceipt: the callback has a single owner and the last assignment wins.
local Codegen = require(script.Parent.Parent.Codegen)
local Placement = require(script.Parent.Parent.Placement)
local Receipts = require(script.Parent.Parent.Receipts)
local Snippets = require(script.Parent.Parent.Snippets)
local Studio = require(script.Parent.Parent.Studio)
local Theme = require(script.Parent.Parent.Theme)
local UI = require(script.Parent.Parent.UI)

local View = {
	id = "sales",
	title = "Vendas",
	nav = true,
	watches = {},
}

type State = { open: string?, placement: Placement.State, showManual: boolean }

local function getState(app: any): State
	local state = app.state.sales
	if not state then
		state = { open = nil, placement = {}, showManual = false }
		app.state.sales = state
	end
	return state
end

local function keyOf(owner: Studio.ReceiptOwner): string
	return `{owner.path}:{owner.assignment.line}`
end

-- The wrapped source for one owner (fresh read, header added when the script has no SDK local).
local function wrappedSource(app: any, owner: Studio.ReceiptOwner): (string?, string?)
	local source = Studio.getSource(owner.script)
	local target: Receipts.Assignment? = nil
	for _, assignment in Receipts.find(source) do
		if assignment.line == owner.assignment.line and not assignment.wrapped then
			target = assignment
		end
	end
	if not target then
		return nil, "o script mudou; olhe de novo"
	end
	local sdk = Receipts.sdkVariable(source)
	local out = Receipts.wrap(source, target, sdk or "RoMetrics")
	if not sdk then
		out = Codegen.withHeader(out, Studio.sdkHeader(app.settings:get("sdkPath")))
	end
	return out, nil
end

local function receiptParam(owner: Studio.ReceiptOwner): string
	local text = string.sub(owner.source, owner.assignment.s, owner.assignment.e)
	return string.match(text, "function%s*[%w_%.:]*%s*%(%s*([%a_][%w_]*)") or "receiptInfo"
end

function View.render(app: any, container: Frame)
	local p = UI.palette
	local state = getState(app)
	local owners = Studio.receiptOwners()
	local sdk = Studio.sdkModule()

	local scroller = UI.scroll({ Parent = container }, 12, 16)
	UI.heading(
		"Vendas",
		"Veja quanto cada produto vende. O RoMetrics só <b>observa</b> a compra: quem entrega o item continua sendo o seu código."
	).Parent =
		scroller

	-- The three kinds of sales.
	local unwrapped = 0
	for _, owner in owners do
		if not owner.assignment.wrapped and not owner.assignment.tracked then
			unwrapped += 1
		end
	end
	local kinds = UI.card(nil, { gap = 2, padding = 10 })
	UI.statusRow({
		state = "ok",
		title = "Game passes",
		detail = "Medidos sozinhos quando o SDK está ligado. Nada a fazer.",
	}).Parent =
		kinds
	UI.statusRow({
		state = if #owners == 0 then "off" elseif unwrapped == 0 and #owners == 1 then "ok" else "warn",
		title = "Developer products (Robux)",
		detail = if #owners == 0
			then "Seu jogo não define ProcessReceipt (ou ainda não vende produtos)."
			elseif unwrapped == 0 and #owners == 1 then "Medidos pelo ProcessReceipt do jogo."
			else "Precisam passar pelo RoMetrics: veja abaixo.",
	}).Parent =
		kinds
	UI.statusRow({
		state = "todo",
		title = "Moeda do jogo (moedas, gemas…)",
		detail = "Compras com dinheiro do jogo: o assistente gera a linha certa.",
		actions = {
			UI.button("Abrir assistente", {
				variant = "ghost",
				onClick = function()
					app.state.measure = { mode = "economy" }
					app:setTab("measure")
				end,
			}),
		},
	}).Parent =
		kinds
	kinds.Parent = scroller

	UI.label("PROCESSRECEIPT NESTE JOGO", { font = Theme.FONT_BOLD, size = 11, color = p.dimText, height = 18 }).Parent =
		scroller

	if #owners > 1 then
		UI.notice(
			`<b>{#owners} lugares definem MarketplaceService.ProcessReceipt.</b> O Roblox só guarda um: o último que rodar apaga os outros, e as vendas deles somem. Deixe só um (normalmente o serviço de loja) e apague os outros.`,
			"danger"
		).Parent =
			scroller
	end

	if #owners == 0 then
		local create = UI.button("Criar ProcessReceipt já medido", {
			variant = "secondary",
			onClick = function()
				UI.confirm(
					"Criar um ProcessReceipt novo?",
					"Só faça isso se o jogo vende developer products e ainda não entrega os itens em nenhum script. O plugin cria ServerScriptService.RoMetricsReceipts com o modelo: você completa a entrega do item.",
					"Criar",
					function()
						local snippet = Snippets.get("processReceipt")
						if not snippet then
							return
						end
						local values = app.settings:values()
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
						app:toast("ProcessReceipt criado: complete a entrega do item.", "success", {
							text = "Desfazer",
							onClick = function()
								app:undo()
							end,
						})
						Studio.openScript(app.plugin, created)
						app:render()
					end
				)
			end,
		})
		UI.card({
			UI.empty(
				"R$",
				"Nenhum ProcessReceipt encontrado",
				"Procurei em todos os scripts do servidor. Se o jogo não vende developer products, está tudo certo: game passes já são medidos.",
				create
			),
		}).Parent =
			scroller
	end

	for _, owner in owners do
		local assignment = owner.assignment
		local key = keyOf(owner)
		local measured = assignment.wrapped or assignment.tracked
		local badge = if assignment.wrapped
			then UI.badge("MEDIDO", p.success)
			elseif assignment.tracked then UI.badge("MEDIDO (trackReceipt)", p.success)
			else UI.badge("NÃO MEDIDO", p.warning)
		local titleRow = UI.row(8, {
			UI.label(owner.script.Name, { font = Theme.FONT_BOLD, size = 15, autoX = true, height = 22 }),
			badge,
		}, { Size = UDim2.new(1, 0, 0, 22) })
		local card = UI.card({
			titleRow,
			UI.label(`{owner.path} · linha {assignment.line}`, { size = 12, color = p.dimText, height = 16 }),
			(UI.code(assignment.preview)),
		}, { gap = 8, stroke = if measured then p.border else p.warning:Lerp(p.border, 0.5) })

		local actions = UI.row(8, {}, { Size = UDim2.new(1, 0, 0, 30) })
		if not measured then
			UI.button(if state.open == key then "Esconder mudança" else "Medir estas vendas", {
				variant = if state.open == key then "secondary" else "primary",
				disabled = sdk == nil,
				onClick = function()
					state.open = if state.open == key then nil else key
					app:render()
				end,
			}).Parent =
				actions
		end
		UI.button("Abrir script", {
			variant = "ghost",
			onClick = function()
				Studio.openScript(app.plugin, owner.script, assignment.line)
			end,
		}).Parent =
			actions
		actions.Parent = card
		if sdk == nil and not measured then
			UI.label("Instale o SDK na aba Início primeiro.", { size = 12, color = p.warning, height = 16 }).Parent =
				card
		end

		if state.open == key and not measured then
			local newSource, err = wrappedSource(app, owner)
			if newSource then
				UI.label(
					"O plugin vai mudar só isto (vermelho sai, verde entra). A decisão de entregar o item continua com o seu código; o RoMetrics anota a venda quando ela é concedida.",
					{ wrap = true, size = 12, color = p.subText }
				).Parent =
					card
				UI.diff(Receipts.diff(Studio.getSource(owner.script), newSource, 1)).Parent = card
				UI.row(8, {
					UI.button("Aplicar mudança", {
						variant = "primary",
						onClick = function()
							local fresh = wrappedSource(app, owner)
							if not fresh then
								app:toast("O script mudou. Olhe a mudança de novo.", "warning")
								app:render()
								return
							end
							local writeErr = Studio.editSource(owner.script, fresh, `medir vendas em {owner.script.Name}`)
							if writeErr then
								app:toast(`Não deu para mudar o script: {writeErr}`, "error")
								return
							end
							state.open = nil
							app:toast(`Pronto! Vendas de {owner.script.Name} agora são medidas.`, "success", {
								text = "Desfazer",
								onClick = function()
									app:undo()
								end,
							})
							app:render()
						end,
					}),
					UI.button("Cancelar", {
						variant = "ghost",
						onClick = function()
							state.open = nil
							app:render()
						end,
					}),
				}, { Size = UDim2.new(1, 0, 0, 30) }).Parent =
					card
			else
				UI.notice(`Não deu para preparar a mudança: {err}`, "warning").Parent = card
			end
		end
		card.Parent = scroller
	end

	-- Manual alternative: RoMetrics.trackReceipt inside the game's own callback.
	if #owners > 0 then
		local manual = UI.card(nil, { gap = 8 })
		UI.row(8, {
			UI.label("Prefere colocar a linha você mesmo?", { font = Theme.FONT_MEDIUM, size = 14, autoX = true }),
			UI.link(if state.showManual then "esconder" else "mostrar", function()
				state.showManual = not state.showManual
				app:render()
			end),
		}).Parent =
			manual
		if state.showManual then
			local param = receiptParam(owners[1])
			UI.label(
				`Em vez de embrulhar, chame <b>RoMetrics.trackReceipt({param})</b> dentro do seu ProcessReceipt, logo antes de devolver <b>PurchaseGranted</b>. Clique nessa linha do script e use o botão abaixo.`,
				{ wrap = true, size = 13, color = p.subText, rich = true }
			).Parent =
				manual
			Placement.render(state.placement, manual)
			UI.button("Inserir trackReceipt", {
				variant = "secondary",
				onClick = function()
					local err = Placement.insert(app, state.placement, {
						build = function(sdkName: string)
							return Codegen.trackReceipt(sdkName, param)
						end,
						label = "inserir trackReceipt",
						fallbackSdkPath = app.settings:get("sdkPath"),
					})
					if err then
						app:toast(err, "warning")
					end
				end,
			}).Parent =
				manual
		end
		manual.Parent = scroller
	end
end

return View

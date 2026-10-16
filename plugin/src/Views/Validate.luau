--!strict
-- "Validação": runs Lint over the registry, tagged instances and script usages.
local Lint = require(script.Parent.Parent.Lint)
local Studio = require(script.Parent.Parent.Studio)
local Theme = require(script.Parent.Parent.Theme)
local UI = require(script.Parent.Parent.UI)

local LABELS = { error = "ERRO", warning = "AVISO", info = "INFO" }

type State = { issues: { Lint.Issue }?, showInfo: boolean, ranAt: string? }

local function getState(app: any): State
	local state = app.state.validate
	if not state then
		state = { issues = nil, showInfo = true, ranAt = nil }
		app.state.validate = state
	end
	return state
end

local View = {
	id = "validate",
	title = "Conferir problemas",
	watches = {},
}

function View.render(app: any, container: Frame)
	local state = getState(app)
	local p = UI.palette
	local colors = { error = p.danger, warning = p.warning, info = p.info }

	local function run()
		state.issues = Lint.run(app.registry, Studio.taggedInfo(), app:usages(true))
		state.ranAt = os.date("%H:%M:%S")
	end
	if not state.issues then
		run()
	end
	local issues = state.issues :: { Lint.Issue }
	local counts = Lint.counts(issues)

	local scroller = UI.scroll({ Parent = container }, 8, 12)
	UI.row(8, {
		UI.button("Validar de novo", {
			variant = "primary",
			onClick = function()
				run()
				app:render()
			end,
		}),
		UI.badge(`{counts.error} erros`, p.danger),
		UI.badge(`{counts.warning} avisos`, p.warning),
		UI.badge(`{counts.info} info`, p.info),
		UI.toggle(state.showInfo, function(value)
			state.showInfo = value
			app:render()
		end),
		UI.label("mostrar info", { color = p.subText, size = 13, autoX = true }),
	}).Parent =
		scroller
	UI.label(
		`Última execução: {state.ranAt or "-"} · regras: nomes (^[A-Za-z0-9_.:-]\{1,64}$), duplicados, props, passos de funil, tags órfãs/gatilhos sem alvo, usos em scripts não registrados.`,
		{ wrap = true, color = p.dimText, size = Theme.SMALL_SIZE }
	).Parent =
		scroller

	if #issues == 0 then
		local panel, body = UI.section("Tudo certo")
		UI.label("Nenhum problema encontrado.", { color = p.success }).Parent = body
		panel.Parent = scroller
		return
	end

	for _, issue in issues do
		if issue.severity == "info" and not state.showInfo then
			continue
		end
		local color = colors[issue.severity]
		local actions: { Instance } = {}
		if issue.ref ~= nil and typeof(issue.ref) == "Instance" then
			local ref = issue.ref :: Instance
			table.insert(
				actions,
				UI.button(if ref:IsA("LuaSourceContainer") then "Abrir" else "Selecionar", {
					variant = "ghost",
					onClick = function()
						if ref:IsA("LuaSourceContainer") then
							Studio.openScript(app.plugin, ref, issue.line)
						else
							Studio.select({ ref })
						end
					end,
				})
			)
		end
		if issue.event then
			local name = issue.event
			table.insert(
				actions,
				UI.button("Ver evento", {
					variant = "ghost",
					onClick = function()
						app.state.events = { search = "", selected = name, draft = nil, isNew = false, collapsed = {} }
						app:setTab("events")
					end,
				})
			)
		end
		local message = UI.label(issue.message, { wrap = true, size = 13 })
		message.Size = UDim2.fromOffset(0, 0)
		message.AutomaticSize = Enum.AutomaticSize.Y
		UI.flex().Parent = message
		local row = UI.new("Frame", {
			BackgroundColor3 = p.panel,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}, {
			UI.badge(LABELS[issue.severity], color),
			message,
		})
		for index, action in actions do
			(action :: any).LayoutOrder = 10 + index
			action.Parent = row
		end
		UI.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
			Parent = row,
		})
		UI.padding(6, 8, 6, 8).Parent = row
		UI.corner(4).Parent = row
		row.Parent = scroller
	end
end

return View

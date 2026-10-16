--!strict
-- "Fluxos": funnel step editor (drag to reorder) + flow diagram (steps, arrows, linking events).
local Flow = require(script.Parent.Parent.Flow)
local Names = require(script.Parent.Parent.Names)
local Registry = require(script.Parent.Parent.Registry)
local Theme = require(script.Parent.Parent.Theme)
local UI = require(script.Parent.Parent.UI)

local ROW = 30

type State = {
	selected: string?,
	steps: { Registry.StepDef }?, -- draft
	dirty: boolean?,
}

local function getState(app: any): State
	local state = app.state.flows
	if not state then
		state = { selected = nil }
		app.state.flows = state
	end
	return state
end

local function cloneSteps(steps: { Registry.StepDef }): { Registry.StepDef }
	local out = {}
	for _, step in steps do
		table.insert(out, { name = step.name, event = step.event })
	end
	return out
end

local View = {
	id = "flows",
	title = "Fluxos",
	watches = {},
}

function View.render(app: any, container: Frame)
	local state = getState(app)
	local p = UI.palette
	local funnelColor = Theme.kindColor("funnel")
	local left, main = app:split(container, 200)
	local funnels = Registry.byKind(app.registry, "funnel")

	local funnel = if state.selected then Registry.find(app.registry, state.selected) else nil
	if funnel and funnel.kind ~= "funnel" then
		funnel = nil
	end
	if not funnel and funnels[1] then
		funnel = funnels[1]
		state.selected = funnels[1].name
		state.steps = nil
	end
	if funnel and not state.steps then
		state.steps = cloneSteps(funnel.steps)
		state.dirty = false
	end

	-- Sidebar ---------------------------------------------------------------------------------------
	local sidebar = UI.scroll({ Parent = left }, 2, 8)
	UI.button("+ Novo funil", {
		variant = "primary",
		onClick = function()
			UI.prompt("Novo funil", "Nome do funil (ex.: Onboarding, Tutorial).", "", function(text)
				local name = Names.sanitize(text)
				local registry = Registry.clone(app.registry)
				local event = Registry.newEvent(name, "funnel")
				event.steps = { { name = "Inicio" } }
				local err = Registry.add(registry, event)
				if err then
					app:toast(err, "error")
					return
				end
				state.selected = name
				state.steps = nil
				app:saveRegistry(registry, `funil {name}`)
			end)
		end,
	}).Parent =
		sidebar
	for _, candidate in funnels do
		UI.listRow(candidate.name, {
			selected = funnel ~= nil and candidate.name == funnel.name,
			prefix = {
				UI.new("Frame", { BackgroundColor3 = funnelColor, Size = UDim2.fromOffset(6, 6) }, { UI.corner(3) }),
			},
			right = { UI.label(tostring(#candidate.steps), { size = 12, color = p.dimText, autoX = true }) },
			onClick = function()
				state.selected = candidate.name
				state.steps = nil
				app:render()
			end,
		}).Parent =
			sidebar
	end
	if #funnels == 0 then
		UI.label(
			"Nenhum funil. Funis medem conversão passo a passo (LogFunnelStepEvent).",
			{ wrap = true, color = p.dimText }
		).Parent =
			sidebar
	end

	local scroller = UI.scroll({ Parent = main }, 10, 12)
	if not funnel then
		UI.label("Crie um funil para editar passos e ver o fluxo.", { color = p.subText }).Parent = scroller
		return
	end
	local current = funnel :: Registry.EventDef
	local steps = state.steps :: { Registry.StepDef }
	local renderMain: () -> ()

	local customOptions = { { label = "(nenhum)", value = nil :: string? } }
	for _, event in Registry.byKind(app.registry, "custom") do
		table.insert(customOptions, { label = event.name, value = event.name })
	end

	local function markDirty()
		state.dirty = true
	end

	local function save()
		local registry = Registry.clone(app.registry)
		local target = Registry.find(registry, current.name)
		if not target then
			return
		end
		local cleaned = {}
		for _, step in steps do
			local name = string.sub(string.gsub(step.name, "^%s*(.-)%s*$", "%1"), 1, Names.MAX_NAME)
			if name ~= "" then
				table.insert(cleaned, { name = name, event = step.event })
			end
		end
		target.steps = cleaned
		state.steps = nil
		app:saveRegistry(registry, `passos de {current.name}`)
	end

	renderMain = function()
		UI.clear(scroller)
		UI.row(8, {
			UI.new("Frame", { BackgroundColor3 = funnelColor, Size = UDim2.fromOffset(10, 10) }, { UI.corner(5) }),
			UI.label(current.name, { font = Theme.FONT_BOLD, size = 18, autoX = true }),
			UI.badge(`{#steps} PASSOS`, funnelColor),
			if state.dirty
				then UI.badge("NÃO SALVO", p.warning)
				else UI.new("Frame", { Size = UDim2.new(), BackgroundTransparency = 1 }),
		}, { Size = UDim2.new(1, 0, 0, 30) }).Parent =
			scroller

		-- Step editor with drag handles ---------------------------------------------------------------
		local addStep = UI.button("+ Passo", {
			variant = "ghost",
			onClick = function()
				table.insert(steps, { name = `Passo{#steps + 1}` })
				markDirty()
				renderMain()
			end,
		})
		local editorPanel, editor = UI.section("Passos (arraste ≡ para reordenar)", { addStep })
		local wrapper = UI.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, math.max(#steps, 1) * ROW),
		})
		local list = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = wrapper })
		UI.vlist(0).Parent = list
		UI.autoOrder(list)
		local indicator = UI.new("Frame", {
			BackgroundColor3 = p.accent,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 2),
			Visible = false,
			ZIndex = 5,
			Parent = wrapper,
		})
		local dragging: number? = nil
		local dropAt = 1

		local function updateDrag(y: number)
			dropAt = Flow.dropIndex(y - wrapper.AbsolutePosition.Y, ROW, #steps)
			indicator.Visible = true
			local lineIndex = if dragging and dropAt > dragging then dropAt else dropAt - 1
			indicator.Position = UDim2.fromOffset(0, lineIndex * ROW - 1)
		end
		local function endDrag()
			if dragging then
				local from = dragging
				dragging = nil
				indicator.Visible = false
				if from ~= dropAt then
					state.steps = Flow.move(steps, from, dropAt)
					steps = state.steps :: { Registry.StepDef }
					markDirty()
					renderMain()
				end
			end
		end
		wrapper.InputChanged:Connect(function(input: InputObject)
			if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
				updateDrag(input.Position.Y)
			end
		end)
		wrapper.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				endDrag()
			end
		end)
		wrapper.MouseLeave:Connect(function()
			if dragging then
				dragging = nil
				indicator.Visible = false
			end
		end)

		for index, step in steps do
			local handle = UI.new("TextButton", {
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				Text = "≡",
				FontFace = Theme.FONT_BOLD,
				TextSize = 16,
				TextColor3 = p.dimText,
				Size = UDim2.fromOffset(18, ROW - 4),
			})
			handle.InputBegan:Connect(function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					dragging = index
					dropAt = index
				end
			end)
			handle.InputEnded:Connect(function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					endDrag()
				end
			end)
			local nameBox = UI.input({
				text = step.name,
				placeholder = "nome do passo",
				onCommit = function(text)
					if text ~= step.name then
						step.name = text
						markDirty()
					end
				end,
			})
			nameBox.Size = UDim2.fromOffset(0, ROW - 6)
			UI.flex().Parent = nameBox
			local stepEvent = UI.dropdown({
				options = customOptions,
				value = step.event,
				placeholder = "(nenhum)",
				width = 150,
				onChange = function(value)
					step.event = value
					markDirty()
					renderMain()
				end,
			})
			stepEvent.Size = UDim2.fromOffset(150, ROW - 6)
			local row = UI.row(6, {
				handle,
				UI.label(tostring(index), { size = 12, color = p.dimText, autoX = true }),
				nameBox,
				stepEvent,
				UI.button("↑", {
					width = 24,
					variant = "ghost",
					onClick = function()
						state.steps = Flow.move(steps, index, index - 1)
						steps = state.steps :: { Registry.StepDef }
						markDirty()
						renderMain()
					end,
				}),
				UI.button("↓", {
					width = 24,
					variant = "ghost",
					onClick = function()
						state.steps = Flow.move(steps, index, index + 1)
						steps = state.steps :: { Registry.StepDef }
						markDirty()
						renderMain()
					end,
				}),
				UI.button("×", {
					width = 24,
					variant = "ghost",
					onClick = function()
						table.remove(steps, index)
						markDirty()
						renderMain()
					end,
				}),
			}, { Size = UDim2.new(1, 0, 0, ROW) })
			row.Parent = list
		end
		if #steps == 0 then
			UI.label("Sem passos.", { color = p.dimText }).Parent = list
		end
		wrapper.Parent = editor
		UI.label("Evento à direita = evento custom que leva a este passo (aparece no diagrama).", {
			color = p.dimText,
			size = Theme.SMALL_SIZE,
			wrap = true,
		}).Parent =
			editor
		UI.row(8, {
			UI.button("Salvar passos", { variant = "primary", onClick = save }),
			UI.button("Descartar", {
				onClick = function()
					state.steps = nil
					app:render()
				end,
			}),
			UI.button("Gerar código", {
				onClick = function()
					app.state.snippets = { id = "funnel", event = current.name }
					app:setTab("snippets")
				end,
			}),
		}).Parent =
			editor
		editorPanel.Parent = scroller

		-- Diagram --------------------------------------------------------------------------------------
		local diagramPanel, diagram = UI.section("Fluxo")
		local preview = table.clone(current)
		preview.steps = steps
		local edges = Flow.edges(app.registry, preview)
		for index, step in steps do
			local card = UI.new("Frame", {
				BackgroundColor3 = p.background,
				Size = UDim2.new(1, 0, 0, 34),
			}, {
				UI.corner(6),
				UI.stroke(funnelColor),
				UI.padding(0, 10, 0, 10),
			})
			UI.hlist(8).Parent = card
			local bubble = UI.new("Frame", {
				BackgroundColor3 = funnelColor,
				Size = UDim2.fromOffset(20, 20),
			}, {
				UI.corner(10),
				UI.new("TextLabel", {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Text = tostring(index),
					FontFace = Theme.FONT_BOLD,
					TextSize = 12,
					TextColor3 = Color3.new(1, 1, 1),
				}),
			})
			bubble.LayoutOrder = 1
			bubble.Parent = card
			local label = UI.label(step.name, { font = Theme.FONT_MEDIUM, autoX = true })
			label.LayoutOrder = 2
			label.Parent = card
			card.Parent = diagram
			local edge = edges[index]
			if edge then
				local via = if #edge.events > 0 then "via " .. table.concat(edge.events, ", ") else "sem evento ligado"
				local connector = UI.new("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 30),
				})
				UI.new("Frame", {
					BackgroundColor3 = funnelColor,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(19, 0),
					Size = UDim2.new(0, 2, 1, -10),
					Parent = connector,
				})
				UI.new("TextLabel", {
					BackgroundTransparency = 1,
					Text = "▼",
					TextSize = 12,
					FontFace = Theme.FONT,
					TextColor3 = funnelColor,
					Position = UDim2.new(0, 14, 1, -14),
					Size = UDim2.fromOffset(12, 14),
					Parent = connector,
				})
				UI.new("TextLabel", {
					BackgroundTransparency = 1,
					Text = via,
					TextSize = 12,
					FontFace = Theme.FONT_CODE,
					TextColor3 = if #edge.events > 0 then p.subText else p.dimText,
					TextXAlignment = Enum.TextXAlignment.Left,
					Position = UDim2.fromOffset(34, 0),
					Size = UDim2.new(1, -34, 1, 0),
					Parent = connector,
				})
				connector.Parent = diagram
			end
		end
		if #steps == 0 then
			UI.label("Adicione passos para ver o fluxo.", { color = p.dimText }).Parent = diagram
		end
		diagramPanel.Parent = scroller
	end

	renderMain()
end

return View

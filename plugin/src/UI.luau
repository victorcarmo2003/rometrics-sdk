--!strict
-- Small instance factory plus the plugin's widgets (UI Labs-like controls), built on native
-- Frames/TextLabels. Views rebuild regions instead of diffing, so components are plain functions.
local Theme = require(script.Parent.Theme)

local UI = {}

UI.palette = Theme.current()
local overlayRoot: GuiObject? = nil

function UI.setPalette(palette: Theme.Palette)
	UI.palette = palette
end

-- Modal layer (dropdown popups, dialogs) covering the whole widget.
function UI.setOverlay(root: GuiObject)
	overlayRoot = root
end

export type Props = { [string]: any }

-- `props.Events = { Activated = fn }`, `props.Changed = { Text = fn(newValue) }`. Children in
-- array order get LayoutOrder = index.
function UI.new(className: string, props: Props?, children: { any }?): any
	local inst: any = Instance.new(className)
	local parent: Instance? = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			elseif key == "Events" then
				for name, handler in value do
					inst[name]:Connect(handler)
				end
			elseif key == "Changed" then
				for property, handler in value do
					inst:GetPropertyChangedSignal(property):Connect(function()
						handler(inst[property])
					end)
				end
			else
				inst[key] = value
			end
		end
	end
	if children then
		for index, child in children do
			if child:IsA("GuiObject") and (child :: GuiObject).LayoutOrder == 0 then
				(child :: GuiObject).LayoutOrder = index
			end
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UI.clear(container: Instance)
	for _, child in container:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") and not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end
end

-- Modifiers ---------------------------------------------------------------------------------------

function UI.corner(radius: number?): any
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.RADIUS) })
end

function UI.stroke(color: Color3?, thickness: number?): any
	return UI.new("UIStroke", {
		Color = color or UI.palette.border,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UI.padding(top: number, right: number?, bottom: number?, left: number?): any
	return UI.new("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right or top),
		PaddingBottom = UDim.new(0, bottom or top),
		PaddingLeft = UDim.new(0, left or right or top),
	})
end

function UI.vlist(gap: number?, align: Enum.HorizontalAlignment?): any
	return UI.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, gap or 0),
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
	})
end

function UI.hlist(gap: number?, valign: Enum.VerticalAlignment?): any
	return UI.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, gap or 0),
		VerticalAlignment = valign or Enum.VerticalAlignment.Center,
	})
end

function UI.flex(mode: Enum.UIFlexMode?): any
	return UI.new("UIFlexItem", { FlexMode = mode or Enum.UIFlexMode.Fill })
end

-- Children parented later (`x.Parent = column`) keep insertion order in list layouts.
local function autoOrder(container: Instance)
	local counter = 1000
	container.ChildAdded:Connect(function(child)
		if child:IsA("GuiObject") and child.LayoutOrder == 0 then
			counter += 1
			child.LayoutOrder = counter
		end
	end)
end
UI.autoOrder = autoOrder

-- Containers --------------------------------------------------------------------------------------

-- Transparent auto-height column.
function UI.column(gap: number?, children: { any }?, props: Props?): any
	local base: Props = {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}
	for key, value in (props or {}) :: Props do
		base[key] = value
	end
	local frame = UI.new("Frame", base, children)
	UI.vlist(gap).Parent = frame
	autoOrder(frame)
	return frame
end

-- Transparent fixed-height row.
function UI.row(gap: number?, children: { any }?, props: Props?): any
	local base: Props = {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.ROW_HEIGHT),
	}
	for key, value in (props or {}) :: Props do
		base[key] = value
	end
	local frame = UI.new("Frame", base, children)
	UI.hlist(gap).Parent = frame
	autoOrder(frame)
	return frame
end

function UI.scroll(props: Props?, gap: number?, pad: number?): any
	local p = UI.palette
	local base: Props = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = p.dimText,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	}
	for key, value in (props or {}) :: Props do
		base[key] = value
	end
	local frame = UI.new("ScrollingFrame", base)
	UI.vlist(gap or 0).Parent = frame
	autoOrder(frame)
	if pad then
		UI.padding(pad).Parent = frame
	end
	return frame
end

-- Panel with a title bar (UI Labs "Controls" style). Returns (panel, content).
function UI.section(title: string, right: { any }?, props: Props?): (any, any)
	local p = UI.palette
	local header = UI.row(6, {
		UI.label(
			string.upper(title),
			{ font = Theme.FONT_BOLD, size = Theme.SMALL_SIZE, color = p.subText, autoX = true }
		),
	}, { Size = UDim2.new(1, 0, 0, 22) })
	if right then
		local spacer = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 1) })
		UI.flex().Parent = spacer
		spacer.LayoutOrder = 50
		spacer.Parent = header
		for index, child in right do
			(child :: any).LayoutOrder = 100 + index
			child.Parent = header
		end
	end
	local content = UI.column(6)
	local base: Props = {
		BackgroundColor3 = p.panel,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}
	for key, value in (props or {}) :: Props do
		base[key] = value
	end
	local panel = UI.new("Frame", base, { header, content })
	UI.vlist(6).Parent = panel
	UI.padding(10).Parent = panel
	UI.corner(6).Parent = panel
	UI.stroke(p.border).Parent = panel
	return panel, content
end

-- Text --------------------------------------------------------------------------------------------

export type LabelOptions = {
	size: number?,
	color: Color3?,
	font: Font?,
	wrap: boolean?,
	autoX: boolean?,
	height: number?,
	alignX: Enum.TextXAlignment?,
	rich: boolean?,
	selectable: boolean?,
}

function UI.label(text: string, opts: LabelOptions?): any
	local o: LabelOptions = opts or {}
	local wrap = o.wrap == true
	return UI.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		FontFace = o.font or Theme.FONT,
		TextSize = o.size or Theme.TEXT_SIZE,
		TextColor3 = o.color or UI.palette.text,
		TextXAlignment = o.alignX or Enum.TextXAlignment.Left,
		TextYAlignment = if wrap then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center,
		TextWrapped = wrap,
		TextTruncate = if wrap or o.autoX then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd,
		RichText = o.rich == true,
		Size = if o.autoX
			then UDim2.fromOffset(0, o.height or Theme.ROW_HEIGHT)
			elseif wrap then UDim2.fromScale(1, 0)
			else UDim2.new(1, 0, 0, o.height or Theme.ROW_HEIGHT),
		AutomaticSize = if o.autoX
			then Enum.AutomaticSize.X
			elseif wrap then Enum.AutomaticSize.Y
			else Enum.AutomaticSize.None,
	})
end

function UI.badge(text: string, color: Color3): any
	local frame = UI.new("Frame", {
		BackgroundColor3 = color,
		BackgroundTransparency = 0.8,
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
	}, {
		UI.new("TextLabel", {
			BackgroundTransparency = 1,
			Text = text,
			FontFace = Theme.FONT_BOLD,
			TextSize = 11,
			TextColor3 = color,
			Size = UDim2.fromOffset(0, 16),
			AutomaticSize = Enum.AutomaticSize.X,
		}),
	})
	UI.corner(8).Parent = frame
	UI.padding(0, 6, 0, 6).Parent = frame
	return frame
end

-- Buttons -----------------------------------------------------------------------------------------

export type ButtonOptions = {
	variant: ("primary" | "secondary" | "danger" | "ghost")?,
	onClick: (() -> ())?,
	width: number?,
	height: number?,
	disabled: boolean?,
	tooltip: string?,
	alignX: Enum.TextXAlignment?,
}

function UI.button(text: string, opts: ButtonOptions?): any
	local o: ButtonOptions = opts or {}
	local p = UI.palette
	local variant = o.variant or "secondary"
	local bg, fg, transparency = p.button, p.buttonText, 0
	if variant == "primary" then
		bg, fg = p.accent, p.accentText
	elseif variant == "danger" then
		bg, fg, transparency = p.danger, p.danger, 0.85
	elseif variant == "ghost" then
		bg, fg, transparency = p.hover, p.text, 1
	end
	if o.disabled then
		fg = p.dimText
	end
	local button = UI.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = bg,
		BackgroundTransparency = transparency,
		Text = text,
		FontFace = Theme.FONT_MEDIUM,
		TextSize = Theme.TEXT_SIZE,
		TextColor3 = fg,
		TextXAlignment = o.alignX or Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(o.width or 0, o.height or Theme.ROW_HEIGHT),
		AutomaticSize = if o.width then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
		Active = not o.disabled,
	})
	UI.corner().Parent = button
	UI.padding(0, 10, 0, 10).Parent = button
	if variant == "secondary" then
		UI.stroke(p.border).Parent = button
	end
	if not o.disabled then
		button.MouseEnter:Connect(function()
			if variant == "ghost" then
				button.BackgroundTransparency = 0
			else
				button.BackgroundColor3 = bg:Lerp(Color3.new(1, 1, 1), 0.08)
			end
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundTransparency = transparency
			button.BackgroundColor3 = bg
		end)
		if o.onClick then
			local onClick = o.onClick
			button.Activated:Connect(function()
				onClick()
			end)
		end
	end
	return button
end

-- Selectable list row (tree items, issue rows).
export type RowOptions = {
	selected: boolean?,
	indent: number?,
	onClick: (() -> ())?,
	height: number?,
	right: { any }?,
	color: Color3?,
	font: Font?,
	prefix: { any }?,
}

function UI.listRow(text: string, opts: RowOptions?): any
	local o: RowOptions = opts or {}
	local p = UI.palette
	local selected = o.selected == true
	local row = UI.new("TextButton", {
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = if selected then p.selected else p.hover,
		BackgroundTransparency = if selected then 0 else 1,
		Size = UDim2.new(1, 0, 0, o.height or Theme.ROW_HEIGHT),
	})
	UI.corner().Parent = row
	UI.padding(0, 6, 0, 6 + (o.indent or 0)).Parent = row
	UI.hlist(6).Parent = row
	local order = 0
	for _, child in (o.prefix or {}) :: { any } do
		order += 1
		(child :: any).LayoutOrder = order
		child.Parent = row
	end
	local label = UI.label(text, { color = o.color or (if selected then p.text else p.subText), font = o.font })
	label.LayoutOrder = 10
	label.Size = UDim2.fromScale(0, 1)
	UI.flex(Enum.UIFlexMode.Fill).Parent = label
	label.Parent = row
	for index, child in (o.right or {}) :: { any } do
		(child :: any).LayoutOrder = 20 + index
		child.Parent = row
	end
	if not selected then
		row.MouseEnter:Connect(function()
			row.BackgroundTransparency = 0
		end)
		row.MouseLeave:Connect(function()
			row.BackgroundTransparency = 1
		end)
	end
	if o.onClick then
		local onClick = o.onClick
		row.Activated:Connect(function()
			onClick()
		end)
	end
	return row
end

-- Inputs ------------------------------------------------------------------------------------------

export type InputOptions = {
	text: string?,
	placeholder: string?,
	onCommit: ((text: string) -> ())?, -- on FocusLost (keeps focus while typing; views can rebuild)
	onChange: ((text: string) -> ())?, -- every keystroke (search boxes)
	multiline: boolean?,
	height: number?,
	code: boolean?,
	readOnly: boolean?,
}

function UI.input(opts: InputOptions?): any
	local o: InputOptions = opts or {}
	local p = UI.palette
	local multiline = o.multiline == true
	local box = UI.new("TextBox", {
		BackgroundColor3 = if o.code then p.codeBackground else p.input,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Text = o.text or "",
		PlaceholderText = o.placeholder or "",
		PlaceholderColor3 = p.dimText,
		TextColor3 = p.text,
		FontFace = if o.code then Theme.FONT_CODE else Theme.FONT,
		TextSize = if o.code then 13 else Theme.TEXT_SIZE,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = if multiline then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center,
		MultiLine = multiline,
		TextWrapped = multiline and not o.code,
		TextEditable = not o.readOnly,
		Size = UDim2.new(1, 0, 0, o.height or Theme.ROW_HEIGHT),
		AutomaticSize = if multiline then Enum.AutomaticSize.Y else Enum.AutomaticSize.None,
		ClipsDescendants = true,
	})
	UI.corner().Parent = box
	UI.padding(if multiline then 6 else 0, 8, if multiline then 6 else 0, 8).Parent = box
	local stroke = UI.stroke(p.inputBorder)
	stroke.Parent = box
	box.Focused:Connect(function()
		stroke.Color = p.accent
	end)
	box.FocusLost:Connect(function()
		stroke.Color = p.inputBorder
		if o.onCommit and not o.readOnly then
			o.onCommit(box.Text)
		end
	end)
	if o.onChange then
		local onChange = o.onChange
		box:GetPropertyChangedSignal("Text"):Connect(function()
			onChange(box.Text)
		end)
	end
	return box
end

-- Switch toggle. Returns the frame; state lives in the caller (onChange receives the new value).
function UI.toggle(value: boolean, onChange: (value: boolean) -> ()): any
	local p = UI.palette
	local state = value
	local track = UI.new("TextButton", {
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(34, 18),
		BackgroundColor3 = if state then p.accent else p.button,
	})
	UI.corner(9).Parent = track
	UI.stroke(if state then p.accent else p.border).Parent = track
	local knob = UI.new("Frame", {
		Size = UDim2.fromOffset(12, 12),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = if state then UDim2.new(1, -15, 0.5, 0) else UDim2.new(0, 3, 0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = track,
	})
	UI.corner(6).Parent = knob
	track.Activated:Connect(function()
		state = not state
		track.BackgroundColor3 = if state then p.accent else p.button;
		(track:FindFirstChildOfClass("UIStroke") :: UIStroke).Color = if state then p.accent else p.border
		knob.Position = if state then UDim2.new(1, -15, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
		onChange(state)
	end)
	return track
end

export type NumberOptions = {
	min: number?,
	max: number?,
	step: number?,
	allowEmpty: boolean?,
	onChange: (value: number?) -> (),
	width: number?,
}

-- Numeric field with -/+ steppers. Empty text = nil when allowEmpty.
function UI.number(value: number?, opts: NumberOptions): any
	local current = value
	local step = opts.step or 1
	local function clamp(n: number): number
		if opts.min then
			n = math.max(n, opts.min)
		end
		if opts.max then
			n = math.min(n, opts.max)
		end
		return n
	end
	local box: TextBox
	local function format(n: number?): string
		if n == nil then
			return ""
		end
		return if n == math.floor(n) then tostring(math.floor(n)) else string.format("%.2f", n)
	end
	local function set(n: number?)
		current = if n then clamp(n) else nil
		box.Text = format(current)
		opts.onChange(current)
	end
	box = UI.input({
		text = format(value),
		placeholder = if opts.allowEmpty then "—" else "0",
		onCommit = function(text: string)
			local parsed = tonumber(text)
			if parsed == nil and not opts.allowEmpty then
				parsed = current or opts.min or 0
			end
			set(parsed)
		end,
	})
	box.Size = UDim2.fromScale(0, 1)
	UI.flex().Parent = box
	local frame = UI.row(4, {
		UI.button("−", {
			width = 26,
			onClick = function()
				set((current or 0) - step)
			end,
		}),
		box,
		UI.button("+", {
			width = 26,
			onClick = function()
				set((current or 0) + step)
			end,
		}),
	}, { Size = UDim2.fromOffset(opts.width or 140, Theme.ROW_HEIGHT) })
	return frame
end

export type Option = { label: string, value: any }

export type DropdownOptions = {
	options: { Option },
	value: any,
	onChange: (value: any) -> (),
	placeholder: string?,
	width: number?,
}

local function closeOverlay(name: string)
	if overlayRoot then
		local existing = overlayRoot:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end
end

function UI.dropdown(opts: DropdownOptions): any
	local p = UI.palette
	local selectedLabel = opts.placeholder or "Selecionar…"
	for _, option in opts.options do
		if option.value == opts.value then
			selectedLabel = option.label
		end
	end
	local button = UI.new("TextButton", {
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = p.input,
		Size = if opts.width
			then UDim2.fromOffset(opts.width, Theme.ROW_HEIGHT)
			else UDim2.new(1, 0, 0, Theme.ROW_HEIGHT),
	})
	UI.corner().Parent = button
	UI.stroke(p.inputBorder).Parent = button
	UI.padding(0, 8, 0, 8).Parent = button
	UI.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = selectedLabel,
		FontFace = Theme.FONT,
		TextSize = Theme.TEXT_SIZE,
		TextColor3 = if opts.value == nil then p.dimText else p.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -16, 1, 0),
		Parent = button,
	})
	local arrow = UI.chevron(true, p.subText)
	arrow.AnchorPoint = Vector2.new(1, 0.5)
	arrow.Position = UDim2.fromScale(1, 0.5)
	arrow.Parent = button
	button.Activated:Connect(function()
		local root = overlayRoot
		if not root then
			return
		end
		closeOverlay("DropdownPopup")
		local blocker = UI.new("TextButton", {
			Name = "DropdownPopup",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 50,
			Parent = root,
		})
		blocker.Activated:Connect(function()
			blocker:Destroy()
		end)
		local rowHeight = 24
		local height = math.min(#opts.options * rowHeight + 8, 240)
		local origin = root.AbsolutePosition
		local x = button.AbsolutePosition.X - origin.X
		local y = button.AbsolutePosition.Y - origin.Y + button.AbsoluteSize.Y + 2
		if y + height > root.AbsoluteSize.Y then
			y = math.max(0, button.AbsolutePosition.Y - origin.Y - height - 2)
		end
		local popup = UI.scroll({
			BackgroundTransparency = 0,
			BackgroundColor3 = p.panel,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(math.max(button.AbsoluteSize.X, 140), height),
			ZIndex = 51,
			Parent = blocker,
		}, 0, 4)
		UI.corner().Parent = popup
		UI.stroke(p.border).Parent = popup
		for _, option in opts.options do
			local row = UI.listRow(option.label, {
				selected = option.value == opts.value,
				height = rowHeight,
				onClick = function()
					blocker:Destroy()
					opts.onChange(option.value)
				end,
			})
			row.ZIndex = 52
			for _, d in row:GetDescendants() do
				if d:IsA("GuiObject") then
					d.ZIndex = 52
				end
			end
			row.Parent = popup
		end
	end)
	return button
end

-- "Label | control" line used by forms (UI Labs Controls look).
function UI.controlRow(label: string, control: any, hint: string?): any
	local p = UI.palette
	local labelWidth = 110
	local labelNode = UI.label(label, { color = p.subText, size = 13 })
	labelNode.Size = UDim2.fromOffset(labelWidth, Theme.ROW_HEIGHT)
	local holder = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -labelWidth - 8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, { control })
	UI.vlist(2).Parent = holder
	if hint then
		local hintLabel = UI.label(hint, { color = p.dimText, size = Theme.SMALL_SIZE, wrap = true })
		hintLabel.LayoutOrder = 2
		hintLabel.Parent = holder
	end
	local row = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, { labelNode, holder })
	UI.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = row,
	})
	return row
end

function UI.divider(): any
	return UI.new("Frame", {
		BackgroundColor3 = UI.palette.border,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 1),
	})
end

-- Dialogs -----------------------------------------------------------------------------------------

export type DialogButton = {
	text: string,
	variant: ("primary" | "secondary" | "danger" | "ghost")?,
	onClick: (() -> ())?,
}

export type DialogOptions = {
	title: string,
	message: string?,
	body: { any }?,
	buttons: { DialogButton },
}

-- Modal over the whole widget. Every button closes the dialog before running its handler.
function UI.dialog(opts: DialogOptions)
	local root = overlayRoot
	if not root then
		return
	end
	local p = UI.palette
	closeOverlay("Dialog")
	local shade = UI.new("TextButton", {
		Name = "Dialog",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 80,
		Parent = root,
	})
	local buttons = {}
	for _, spec in opts.buttons do
		table.insert(
			buttons,
			UI.button(spec.text, {
				variant = spec.variant,
				onClick = function()
					shade:Destroy()
					if spec.onClick then
						spec.onClick()
					end
				end,
			})
		)
	end
	local content: { any } = {
		UI.label(opts.title, { font = Theme.FONT_BOLD, size = 16 }),
	}
	if opts.message then
		table.insert(content, UI.label(opts.message, { wrap = true, color = p.subText }))
	end
	for _, child in (opts.body or {}) :: { any } do
		table.insert(content, child)
	end
	local buttonRow = UI.row(8, buttons);
	(buttonRow:FindFirstChildOfClass("UIListLayout") :: UIListLayout).HorizontalAlignment =
		Enum.HorizontalAlignment.Right
	table.insert(content, buttonRow)
	local card = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -40, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = p.background,
		Parent = shade,
	}, content)
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(460, math.huge), Parent = card })
	UI.vlist(10).Parent = card
	UI.padding(16).Parent = card
	UI.corner(8).Parent = card
	UI.stroke(p.border).Parent = card
	for _, d in shade:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 81
		end
	end
end

function UI.confirm(
	title: string,
	message: string,
	confirmText: string,
	onConfirm: () -> (),
	danger: boolean?,
	body: { any }?
)
	UI.dialog({
		title = title,
		message = message,
		body = body,
		buttons = {
			{ text = "Cancelar", variant = "secondary" },
			{ text = confirmText, variant = if danger then "danger" else "primary", onClick = onConfirm },
		},
	})
end

-- Single-field prompt (rename, new funnel step…).
function UI.prompt(title: string, message: string?, initial: string, onSubmit: (text: string) -> ())
	local value = initial
	local box = UI.input({
		text = initial,
		onChange = function(text)
			value = text
		end,
	})
	UI.dialog({
		title = title,
		message = message,
		body = { box },
		buttons = {
			{ text = "Cancelar", variant = "secondary" },
			{
				text = "OK",
				variant = "primary",
				onClick = function()
					onSubmit(value)
				end,
			},
		},
	})
	task.defer(function()
		if box.Parent then
			box:CaptureFocus()
		end
	end)
end

-- Expand/collapse arrow. BuilderSans has no triangle glyphs (they render as boxes) and Rotation
-- is ignored under ClipsDescendants, so open/closed are two glyphs the font does have.
function UI.chevron(open: boolean, color: Color3?): any
	return UI.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = if open then "˅" else "›",
		FontFace = Theme.FONT_BOLD,
		TextSize = 16,
		TextColor3 = color or UI.palette.subText,
		Size = UDim2.fromOffset(12, 16),
	})
end

-- Brand ---------------------------------------------------------------------------------------------

-- RoMetrics logo (docs/public/logo.svg): blue rounded square with three rising bars.
-- Axis-aligned rounded rects only, so native Frames stay crisp at any size (no image upload).
function UI.logo(size: number?): any
	local s = size or 20
	local unit = s / 24
	local bars = {}
	for _, bar in { { 6, 12.5, 5.5, 0.45 }, { 10.7, 9, 9, 0.2 }, { 15.4, 5.5, 12.5, 0 } } do
		table.insert(
			bars,
			UI.new("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = bar[4],
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(math.floor(bar[1] * unit + 0.5), math.floor(bar[2] * unit + 0.5)),
				Size = UDim2.fromOffset(math.max(2, math.floor(2.6 * unit + 0.5)), math.floor(bar[3] * unit + 0.5)),
			}, { UI.corner(math.max(1, math.floor(1.1 * unit))) })
		)
	end
	local frame = UI.new("Frame", {
		Name = "Logo",
		BackgroundColor3 = Theme.ACCENT,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(s, s),
	}, bars)
	UI.corner(math.floor(6 * unit + 0.5)).Parent = frame
	return frame
end

-- Status pill: colored dot + text, e.g. "SDK instalado".
function UI.pill(text: string, color: Color3, onClick: (() -> ())?): any
	local p = UI.palette
	local pill = UI.new(if onClick then "TextButton" else "Frame", {
		BackgroundColor3 = color,
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
	}, {
		UI.new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.fromOffset(6, 6) }, { UI.corner(3) }),
		UI.label(text, { size = Theme.SMALL_SIZE, font = Theme.FONT_MEDIUM, color = p.text, autoX = true, height = 22 }),
	})
	if onClick then
		(pill :: any).AutoButtonColor = false;
		(pill :: any).Text = "";
		(pill :: any).Activated:Connect(onClick)
	end
	UI.hlist(6).Parent = pill
	UI.corner(11).Parent = pill
	UI.padding(0, 10, 0, 8).Parent = pill
	return pill
end

export type StepOptions = {
	number: number,
	title: string,
	description: string,
	state: "done" | "todo" | "optional",
	status: string?,
	actions: { any }?,
	extra: { any }?,
}

-- Numbered checklist card for the Home tab.
function UI.step(o: StepOptions): any
	local p = UI.palette
	local done = o.state == "done"
	local badgeColor = if done then p.success elseif o.state == "todo" then p.accent else p.dimText
	local badge = UI.new("Frame", {
		BackgroundColor3 = badgeColor,
		BackgroundTransparency = if done then 0 else 0.8,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(24, 24),
	}, {
		UI.new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Text = if done then "✓" else tostring(o.number),
			FontFace = Theme.FONT_BOLD,
			TextSize = 13,
			TextColor3 = if done then Color3.new(1, 1, 1) else badgeColor,
		}),
	})
	UI.corner(12).Parent = badge

	local titleRow = UI.row(8, {
		UI.label(o.title, { font = Theme.FONT_BOLD, size = 15, autoX = true, height = 24 }),
	}, { Size = UDim2.new(1, 0, 0, 24) })
	if o.status then
		local statusLabel =
			UI.label(o.status, { size = Theme.SMALL_SIZE, color = if done then p.success else p.subText, autoX = true, height = 24 })
		statusLabel.LayoutOrder = 10
		statusLabel.Parent = titleRow
	end

	local body = UI.column(8, {
		titleRow,
		UI.label(o.description, { wrap = true, color = p.subText, size = 13 }),
	})
	body.Size = UDim2.fromScale(0, 0)
	UI.flex().Parent = body
	for _, child in (o.extra or {}) :: { any } do
		child.Parent = body
	end
	if o.actions and #o.actions > 0 then
		local actions = UI.row(8, o.actions, { Size = UDim2.new(1, 0, 0, 28) })
		actions.Parent = body
	end

	local card = UI.new("Frame", {
		BackgroundColor3 = p.panel,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, { badge, body })
	local layout = UI.hlist(12, Enum.VerticalAlignment.Top)
	layout.Parent = card
	UI.padding(12, 14, 12, 12).Parent = card
	UI.corner(8).Parent = card
	UI.stroke(if o.state == "todo" then p.accent:Lerp(p.border, 0.55) else p.border).Parent = card
	return card
end

-- Tip/notice box (info, warning, success).
function UI.notice(text: string, kind: ("info" | "warning" | "success" | "danger")?): any
	local p = UI.palette
	local color = if kind == "warning"
		then p.warning
		elseif kind == "success" then p.success
		elseif kind == "danger" then p.danger
		else p.accent
	local box = UI.new("Frame", {
		BackgroundColor3 = color,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		UI.label(text, { wrap = true, size = 13, color = p.text, rich = true }),
	})
	UI.corner(6).Parent = box
	UI.padding(8, 10, 8, 10).Parent = box
	UI.stroke(color:Lerp(p.border, 0.5)).Parent = box
	return box
end

return UI

--!strict
-- Colors follow the Studio theme (light/dark) with the RoMetrics accent on top.

local Theme = {}

export type Palette = {
	background: Color3,
	panel: Color3,
	sidebar: Color3,
	input: Color3,
	inputBorder: Color3,
	border: Color3,
	hover: Color3,
	selected: Color3,
	text: Color3,
	subText: Color3,
	dimText: Color3,
	button: Color3,
	buttonText: Color3,
	accent: Color3,
	accentText: Color3,
	accentSoft: Color3,
	success: Color3,
	warning: Color3,
	danger: Color3,
	info: Color3,
	codeBackground: Color3,
	card: Color3,
	cardHover: Color3,
	cardBorder: Color3,
	isDark: boolean,
}

Theme.ACCENT = Color3.fromHex("#2F7BFF")
Theme.FONT = Font.fromEnum(Enum.Font.BuilderSans)
Theme.FONT_MEDIUM = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium)
Theme.FONT_BOLD = Font.fromEnum(Enum.Font.BuilderSansBold)
Theme.FONT_CODE = Font.fromEnum(Enum.Font.RobotoMono)
Theme.TEXT_SIZE = 14
Theme.SMALL_SIZE = 12
Theme.ROW_HEIGHT = 28
Theme.RADIUS = 6

local function studioTheme(): any
	local ok, theme = pcall(function()
		return (settings() :: any).Studio.Theme
	end)
	return if ok then theme else nil
end

local function color(
	theme: any,
	guide: Enum.StudioStyleGuideColor,
	fallback: Color3,
	modifier: Enum.StudioStyleGuideModifier?
): Color3
	if not theme then
		return fallback
	end
	local ok, value = pcall(function()
		return theme:GetColor(guide, modifier or Enum.StudioStyleGuideModifier.Default)
	end)
	return if ok then value else fallback
end

local function luminance(c: Color3): number
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

function Theme.current(): Palette
	local theme = studioTheme()
	local C = Enum.StudioStyleGuideColor
	local background = color(theme, C.MainBackground, Color3.fromRGB(46, 46, 46))
	local isDark = luminance(background) < 0.5
	local accent = Theme.ACCENT
	return {
		background = background,
		panel = color(theme, C.Titlebar, Color3.fromRGB(53, 53, 53)),
		sidebar = color(theme, C.ScrollBarBackground, Color3.fromRGB(41, 41, 41)),
		input = color(theme, C.InputFieldBackground, Color3.fromRGB(37, 37, 37)),
		inputBorder = color(theme, C.InputFieldBorder, Color3.fromRGB(26, 26, 26)),
		border = color(theme, C.Border, Color3.fromRGB(34, 34, 34)),
		hover = color(theme, C.Item, Color3.fromRGB(66, 66, 66), Enum.StudioStyleGuideModifier.Hover),
		selected = accent:Lerp(background, if isDark then 0.55 else 0.75),
		text = color(theme, C.MainText, Color3.fromRGB(204, 204, 204)),
		subText = color(theme, C.SubText, Color3.fromRGB(170, 170, 170)),
		dimText = color(theme, C.DimmedText, Color3.fromRGB(102, 102, 102)),
		button = color(theme, C.Button, Color3.fromRGB(60, 60, 60)),
		buttonText = color(theme, C.ButtonText, Color3.fromRGB(204, 204, 204)),
		accent = accent,
		accentText = Color3.new(1, 1, 1),
		accentSoft = accent:Lerp(background, if isDark then 0.75 else 0.85),
		success = Color3.fromHex(if isDark then "#3FB27F" else "#1E8A5A"),
		warning = Color3.fromHex(if isDark then "#E3B341" else "#A86B00"),
		danger = Color3.fromHex(if isDark then "#F0605D" else "#C4312E"),
		info = accent,
		codeBackground = color(theme, C.ScriptBackground, Color3.fromRGB(30, 30, 30)),
		-- Cards sit a little above the background (lighter in dark mode, white in light mode).
		card = if isDark then background:Lerp(Color3.new(1, 1, 1), 0.05) else Color3.new(1, 1, 1),
		cardBorder = if isDark
			then background:Lerp(Color3.new(1, 1, 1), 0.12)
			else background:Lerp(Color3.new(0, 0, 0), 0.12),
		cardHover = if isDark
			then background:Lerp(Color3.new(1, 1, 1), 0.08)
			else accent:Lerp(Color3.new(1, 1, 1), 0.94),
		isDark = isDark,
	}
end

-- Calls `callback` when the Studio theme changes. Returns a disconnect function.
function Theme.onChanged(callback: () -> ()): () -> ()
	local ok, connection = pcall(function()
		return (settings() :: any).Studio.ThemeChanged:Connect(callback)
	end)
	return function()
		if ok and connection then
			connection:Disconnect()
		end
	end
end

-- Color per kind, used by the tree badges and the flow diagram.
function Theme.kindColor(kind: string): Color3
	if kind == "funnel" then
		return Color3.fromHex("#9B6BFF")
	elseif kind == "progression" then
		return Color3.fromHex("#3FB27F")
	elseif kind == "economy" then
		return Color3.fromHex("#E3B341")
	end
	return Theme.ACCENT
end

return Theme

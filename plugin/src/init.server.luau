--!strict
-- RoMetrics Studio plugin entry: toolbar button + dock widget.
local RunService = game:GetService("RunService")

-- Plugins also load inside play-test servers/clients; only the edit session needs the UI.
if RunService:IsRunning() then
	return
end

local App = require(script.App)

local views = {
	require(script.Views.Events),
	require(script.Views.Track),
	require(script.Views.Snippets),
	require(script.Views.Flows),
	require(script.Views.Validate),
	require(script.Views.Config),
} :: { any }

local toolbar = plugin:CreateToolbar("RoMetrics")
local button = toolbar:CreateButton("RoMetrics", "Eventos, tags, snippets e funis do RoMetrics", "")
button.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 560, 640, 420, 360)
local okAsync, asyncWidget = pcall(function()
	return (plugin :: any):CreateDockWidgetPluginGuiAsync("RoMetricsWidget", widgetInfo)
end)
-- Fallback for Studio builds without the Async variant.
-- selene: allow(deprecated)
local widget: DockWidgetPluginGui = if okAsync and asyncWidget
	then asyncWidget
	else plugin:CreateDockWidgetPluginGui("RoMetricsWidget", widgetInfo)
widget.Name = "RoMetrics"
widget.Title = "RoMetrics"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local app: any = nil

local function ensureApp()
	if not app then
		local ok, result = pcall(App.new, plugin, widget, views)
		if ok then
			app = result
		else
			warn(`[RoMetrics plugin] failed to start: {result}`)
		end
	end
end

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	button:SetActive(widget.Enabled)
	if widget.Enabled then
		ensureApp()
	end
end)

if widget.Enabled then
	button:SetActive(true)
	ensureApp()
end

plugin.Unloading:Connect(function()
	if app then
		app:destroy()
	end
end)

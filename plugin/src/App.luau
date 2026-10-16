--!strict
-- Shell: header with tabs, view area, status bar, modal overlay. Owns shared state (registry,
-- settings, per-view UI state) and re-renders the active view when the place changes.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")

local Registry = require(script.Parent.Registry)
local Settings = require(script.Parent.Settings)
local Studio = require(script.Parent.Studio)
local Tagging = require(script.Parent.Tagging)
local Theme = require(script.Parent.Theme)
local UI = require(script.Parent.UI)
local Lint = require(script.Parent.Lint)

export type View = {
	id: string,
	title: string,
	-- Re-render triggers this view cares about.
	watches: { selection: boolean?, tags: boolean? },
	render: (app: App, container: Frame) -> (),
}

export type App = {
	plugin: Plugin,
	widget: DockWidgetPluginGui,
	settings: Settings.Store,
	registry: Registry.Registry,
	registryNotes: { string },
	registryExists: boolean,
	tab: string,
	state: { [string]: any },
	highlighter: Tagging.Highlighter,
	views: { View },
	render: (self: App) -> (),
	setTab: (self: App, id: string) -> (),
	reloadRegistry: (self: App) -> (),
	saveRegistry: (self: App, registry: Registry.Registry, label: string, extra: (() -> ())?) -> string?,
	toast: (self: App, message: string, kind: ("info" | "success" | "warning" | "error")?) -> (),
	usages: (self: App, force: boolean?) -> { Lint.ScriptUsage },
	split: (self: App, container: Frame, leftWidth: number?) -> (Frame, Frame),
	destroy: (self: App) -> (),
}

local App = {}

local USAGE_CACHE_SECONDS = 5

function App.new(plugin: Plugin, widget: DockWidgetPluginGui, views: { View }): App
	local settings = Settings.new(plugin)
	local self = {
		plugin = plugin,
		widget = widget,
		settings = settings,
		registry = Registry.empty(),
		registryNotes = {},
		registryExists = false,
		tab = settings:get("lastTab"),
		state = {},
		views = views,
	} :: App

	local connections: { RBXScriptConnection } = {}
	local root: Frame? = nil
	local content: Frame? = nil
	local statusLabel: TextLabel? = nil
	local toastLabel: TextLabel? = nil
	local toastToken = 0
	local usageCache: { Lint.ScriptUsage }? = nil
	local usageAt = 0
	local lastSerialized: string? = nil
	local renderQueued = false
	local registryConnection: RBXScriptConnection? = nil

	self.highlighter = Tagging.highlighter(Theme.ACCENT)

	local function currentView(): View
		for _, view in views do
			if view.id == self.tab then
				return view
			end
		end
		return views[1]
	end

	local function updateStatus()
		if not statusLabel then
			return
		end
		local text
		if self.registryExists then
			text =
				`{Registry.MODULE_NAME}: {#self.registry.events} eventos · {#Tagging.tagged()} instâncias rastreadas`
		else
			text = `{Registry.MODULE_NAME} ainda não existe (criado ao salvar o primeiro evento)`
		end
		if #self.registryNotes > 0 then
			text ..= ` · {#self.registryNotes} aviso(s) ao ler o registro`
		end
		statusLabel.Text = text
	end

	local function renderView()
		local container = content
		if not container then
			return
		end
		UI.clear(container)
		local view = currentView()
		local ok, err = pcall(view.render :: any, self, container)
		if not ok then
			UI.clear(container)
			local message =
				UI.label(`Erro ao desenhar a aba {view.title}: {err}`, { wrap = true, color = UI.palette.danger })
			message.Parent = container
			warn(`[RoMetrics plugin] {err}`)
		end
		updateStatus()
	end

	local function buildShell()
		if root then
			root:Destroy()
		end
		UI.setPalette(Theme.current())
		local p = UI.palette
		local tabs = {}
		for _, view in views do
			local active = view.id == self.tab
			local tab = UI.new("TextButton", {
				AutoButtonColor = false,
				Text = view.title,
				FontFace = if active then Theme.FONT_BOLD else Theme.FONT_MEDIUM,
				TextSize = Theme.TEXT_SIZE,
				TextColor3 = if active then p.text else p.subText,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(0, 1),
				AutomaticSize = Enum.AutomaticSize.X,
			}, {
				UI.padding(0, 10, 0, 10),
				UI.new("Frame", {
					BackgroundColor3 = p.accent,
					BorderSizePixel = 0,
					BackgroundTransparency = if active then 0 else 1,
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, -10, 1, 0),
					Size = UDim2.new(1, 20, 0, 2),
				}),
			})
			tab.Activated:Connect(function()
				self:setTab(view.id)
			end)
			table.insert(tabs, tab)
		end
		local brand = UI.row(6, {
			UI.new("Frame", { BackgroundColor3 = p.accent, Size = UDim2.fromOffset(10, 10) }, { UI.corner(3) }),
			UI.label("RoMetrics", { font = Theme.FONT_BOLD, size = 15, autoX = true }),
		}, { Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X })
		UI.padding(0, 14, 0, 10).Parent = brand
		local tabStrip = UI.new("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(0, 1),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			ScrollingDirection = Enum.ScrollingDirection.X,
			ScrollBarThickness = 0,
		}, tabs)
		UI.hlist(0).Parent = tabStrip
		UI.flex().Parent = tabStrip
		local header = UI.new("Frame", {
			Name = "Header",
			BackgroundColor3 = p.panel,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 36),
		}, { brand, tabStrip })
		UI.hlist(0, Enum.VerticalAlignment.Center).Parent = header
		UI.new("Frame", {
			BackgroundColor3 = p.border,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 1),
			Parent = header,
		})

		local body = UI.new("Frame", {
			Name = "Content",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 36),
			Size = UDim2.new(1, 0, 1, -36 - 24),
			ClipsDescendants = true,
		})
		content = body

		local status = UI.label("", { size = Theme.SMALL_SIZE, color = p.subText })
		status.Size = UDim2.fromScale(0.6, 1)
		statusLabel = status
		local toast = UI.label("", { size = Theme.SMALL_SIZE, color = p.subText, alignX = Enum.TextXAlignment.Right })
		toast.Size = UDim2.fromScale(0.4, 1)
		toast.Position = UDim2.fromScale(0.6, 0)
		toastLabel = toast
		local statusBar = UI.new("Frame", {
			Name = "Status",
			BackgroundColor3 = p.panel,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 24),
		}, { status, toast })
		UI.padding(0, 10, 0, 10).Parent = statusBar

		local overlay = UI.new("Frame", {
			Name = "Overlay",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 50,
		})
		UI.setOverlay(overlay)

		local newRoot = UI.new("Frame", {
			Name = "RoMetrics",
			BackgroundColor3 = p.background,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
		}, { header, body, statusBar, overlay })
		newRoot.Parent = widget
		root = newRoot
		renderView()
	end

	local function watchRegistryModule()
		if registryConnection then
			registryConnection:Disconnect()
			registryConnection = nil
		end
		local module = Studio.registryModule()
		if module then
			registryConnection = module:GetPropertyChangedSignal("Source"):Connect(function()
				-- Undo/redo or hand edits: reload when the text differs from what we last wrote.
				task.defer(function()
					local current = Studio.getSource(module)
					if current ~= lastSerialized then
						self:reloadRegistry()
					end
				end)
			end)
		end
	end

	local function queueRender()
		if renderQueued then
			return
		end
		renderQueued = true
		task.delay(0.15, function()
			renderQueued = false
			renderView()
		end)
	end

	function self.render(_: App)
		buildShell()
	end

	function self.setTab(_: App, id: string)
		self.tab = id
		settings:set("lastTab", id)
		buildShell()
	end

	function self.reloadRegistry(_: App)
		local registry, notes, exists = Studio.loadRegistry()
		self.registry = registry
		self.registryNotes = notes
		self.registryExists = exists
		local module = Studio.registryModule()
		lastSerialized = if module then Studio.getSource(module) else nil
		watchRegistryModule()
		queueRender()
	end

	function self.saveRegistry(_: App, registry: Registry.Registry, label: string, extra: (() -> ())?): string?
		local source = Registry.serialize(registry)
		local err = Tagging.record(`RoMetrics: {label}`, function()
			Studio.writeRegistry(registry)
			if extra then
				extra()
			end
		end)
		if err then
			self:toast(`Falha ao salvar: {err}`, "error")
			return err
		end
		lastSerialized = source
		self.registry = registry
		self.registryNotes = {}
		self.registryExists = true
		watchRegistryModule()
		self:toast(`Salvo: {label}`, "success")
		queueRender()
		return nil
	end

	function self.toast(_: App, message: string, kind)
		local label = toastLabel
		if not label then
			return
		end
		local p = UI.palette
		label.Text = message
		label.TextColor3 = if kind == "error"
			then p.danger
			elseif kind == "warning" then p.warning
			elseif kind == "success" then p.success
			else p.subText
		toastToken += 1
		local token = toastToken
		task.delay(5, function()
			if token == toastToken and label.Parent then
				label.Text = ""
			end
		end)
	end

	function self.usages(_: App, force: boolean?): { Lint.ScriptUsage }
		if force or not usageCache or os.clock() - usageAt > USAGE_CACHE_SECONDS then
			usageCache = Studio.usages()
			usageAt = os.clock()
		end
		return usageCache :: { Lint.ScriptUsage }
	end

	function self.split(_: App, container: Frame, leftWidth: number?): (Frame, Frame)
		local p = UI.palette
		local width = leftWidth or 220
		local left = UI.new("Frame", {
			Name = "Sidebar",
			BackgroundColor3 = p.sidebar,
			BorderSizePixel = 0,
			Size = UDim2.new(0, width, 1, 0),
			Parent = container,
		})
		UI.new("Frame", {
			BackgroundColor3 = p.border,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(width, 0),
			Size = UDim2.new(0, 1, 1, 0),
			Parent = container,
		})
		local main = UI.new("Frame", {
			Name = "Main",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(width + 1, 0),
			Size = UDim2.new(1, -width - 1, 1, 0),
			Parent = container,
		})
		return left, main
	end

	function self.destroy(_: App)
		for _, connection in connections do
			connection:Disconnect()
		end
		if registryConnection then
			registryConnection:Disconnect()
		end
		self.highlighter:destroy()
		if root then
			root:Destroy()
		end
	end

	-- Place watchers.
	table.insert(
		connections,
		ReplicatedStorage.ChildAdded:Connect(function(child)
			if child.Name == Registry.MODULE_NAME then
				task.defer(function()
					self:reloadRegistry()
				end)
			end
		end)
	)
	table.insert(
		connections,
		ReplicatedStorage.ChildRemoved:Connect(function(child)
			if child.Name == Registry.MODULE_NAME then
				self:reloadRegistry()
			end
		end)
	)
	table.insert(
		connections,
		Selection.SelectionChanged:Connect(function()
			if widget.Enabled and currentView().watches.selection then
				queueRender()
			end
		end)
	)
	local function onTagsChanged()
		if widget.Enabled and currentView().watches.tags then
			queueRender()
		else
			updateStatus()
		end
	end
	table.insert(connections, CollectionService:GetInstanceAddedSignal(Tagging.TAG):Connect(onTagsChanged))
	table.insert(connections, CollectionService:GetInstanceRemovedSignal(Tagging.TAG):Connect(onTagsChanged))
	table.insert(
		connections,
		widget:GetPropertyChangedSignal("Enabled"):Connect(function()
			if widget.Enabled then
				self:reloadRegistry()
			end
		end)
	)
	local disconnectTheme = Theme.onChanged(function()
		buildShell()
	end)
	table.insert(
		connections,
		{
			Disconnect = function()
				disconnectTheme()
			end,
		} :: any
	)

	self.highlighter:setEnabled(settings:get("highlight"))
	local registry, notes, exists = Studio.loadRegistry()
	self.registry = registry
	self.registryNotes = notes
	self.registryExists = exists
	local module = Studio.registryModule()
	lastSerialized = if module then Studio.getSource(module) else nil
	watchRegistryModule()
	buildShell()
	return self
end

return App

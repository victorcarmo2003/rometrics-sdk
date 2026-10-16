--!strict
-- Shell: header (logo + SDK status), grouped sidebar nav, view area, status bar and modal overlay.
-- Owns shared state (registry, settings, per-view UI state) and re-renders the active view when
-- the place changes.
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

	-- Sidebar groups, in workflow order (labels already uppercase: string.upper is ASCII-only).
	-- Views missing here land in the last group.
	local NAV: { { label: string, ids: { string } } } = {
		{ label = "COMEÇAR", ids = { "home" } },
		{ label = "EVENTOS", ids = { "events", "track", "snippets", "flows" } },
		{ label = "CONFERIR", ids = { "validate", "config" } },
	}
	local RAIL_WIDTH = 132
	local HEADER_HEIGHT = 44
	local STATUS_HEIGHT = 24

	local function navItem(view: View): TextButton
		local p = UI.palette
		local active = view.id == self.tab
		local item = UI.new("TextButton", {
			Name = view.id,
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = if active then p.accentSoft else p.hover,
			BackgroundTransparency = if active then 0 else 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 30),
		}, {
			UI.new("Frame", {
				Name = "Bar",
				BackgroundColor3 = p.accent,
				BackgroundTransparency = if active then 0 else 1,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, 7),
				Size = UDim2.fromOffset(3, 16),
			}, { UI.corner(2) }),
			UI.new("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(12, 0),
				Size = UDim2.new(1, -16, 1, 0),
				Text = view.title,
				FontFace = if active then Theme.FONT_BOLD else Theme.FONT_MEDIUM,
				TextSize = 14,
				TextColor3 = if active then p.text else p.subText,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
		})
		UI.corner(6).Parent = item
		if not active then
			item.MouseEnter:Connect(function()
				item.BackgroundTransparency = 0
			end)
			item.MouseLeave:Connect(function()
				item.BackgroundTransparency = 1
			end)
		end
		item.Activated:Connect(function()
			self:setTab(view.id)
		end)
		return item
	end

	local function buildRail(): (Frame, Frame)
		local p = UI.palette
		local byId: { [string]: View } = {}
		local placed: { [string]: boolean } = {}
		for _, view in views do
			byId[view.id] = view
		end
		local rail = UI.scroll({
			Name = "Nav",
			BackgroundColor3 = p.sidebar,
			BackgroundTransparency = 0,
			Position = UDim2.fromOffset(0, HEADER_HEIGHT),
			Size = UDim2.new(0, RAIL_WIDTH, 1, -HEADER_HEIGHT - STATUS_HEIGHT),
			ScrollBarThickness = 0,
		}, 2, 8)
		for index, group in NAV do
			local items: { View } = {}
			for _, id in group.ids do
				if byId[id] then
					table.insert(items, byId[id])
					placed[id] = true
				end
			end
			if index == #NAV then
				for _, view in views do
					if not placed[view.id] then
						table.insert(items, view)
					end
				end
			end
			if #items > 0 then
				local heading = UI.label(group.label, {
					font = Theme.FONT_BOLD,
					size = 11,
					color = p.dimText,
					height = if index == 1 then 20 else 30,
				})
				heading.TextYAlignment = Enum.TextYAlignment.Bottom
				UI.padding(0, 0, 4, 12).Parent = heading
				heading.Parent = rail
				for _, view in items do
					navItem(view).Parent = rail
				end
			end
		end
		local border = UI.new("Frame", {
			Name = "NavBorder",
			BackgroundColor3 = p.border,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromOffset(RAIL_WIDTH, HEADER_HEIGHT),
			Size = UDim2.new(0, 1, 1, -HEADER_HEIGHT - STATUS_HEIGHT),
		})
		return rail, border
	end

	local function buildHeader(): Frame
		local p = UI.palette
		local sdk = Studio.sdkModule()
		local version = if sdk then sdk:GetAttribute("RM_Version") else nil
		local brand = UI.row(10, {
			UI.logo(22),
			UI.column(0, {
				UI.label("RoMetrics", { font = Theme.FONT_BOLD, size = 15, height = 18 }),
				UI.label("Analytics para o seu jogo", { size = 11, color = p.dimText, height = 14 }),
			}, { Size = UDim2.fromOffset(170, 0) }),
		}, { Size = UDim2.new(1, -180, 1, 0) })
		local pill = if sdk
			then UI.pill(if type(version) == "string" then `SDK {version}` else "SDK instalado", p.success, function()
				self:setTab("home")
			end)
			else UI.pill("SDK não instalado", p.warning, function()
				self:setTab("home")
			end)
		pill.AnchorPoint = Vector2.new(1, 0.5)
		pill.Position = UDim2.fromScale(1, 0.5)
		local header = UI.new("Frame", {
			Name = "Header",
			BackgroundColor3 = p.panel,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
		}, { brand, pill })
		UI.padding(0, 12, 0, 12).Parent = header
		UI.new("Frame", {
			BackgroundColor3 = p.border,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, -12, 1, 0),
			Size = UDim2.new(1, 24, 0, 1),
			Parent = header,
		})
		return header
	end

	local function buildShell()
		if root then
			root:Destroy()
		end
		UI.setPalette(Theme.current())
		local p = UI.palette

		local body = UI.new("Frame", {
			Name = "Content",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(RAIL_WIDTH, HEADER_HEIGHT),
			Size = UDim2.new(1, -RAIL_WIDTH, 1, -HEADER_HEIGHT - STATUS_HEIGHT),
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
			Size = UDim2.new(1, 0, 0, STATUS_HEIGHT),
		}, { status, toast })
		UI.padding(0, 10, 0, 10).Parent = statusBar

		local overlay = UI.new("Frame", {
			Name = "Overlay",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 50,
		})
		UI.setOverlay(overlay)

		local rail, railBorder = buildRail()
		local newRoot = UI.new("Frame", {
			Name = "RoMetrics",
			BackgroundColor3 = p.background,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
		}, { buildHeader(), rail, railBorder, body, statusBar, overlay })
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
		-- Keep the main pane usable on narrow docks: the list never takes more than ~40%.
		local available = container.AbsoluteSize.X
		local width = leftWidth or 220
		if available > 0 then
			width = math.clamp(math.floor(available * 0.4), math.min(150, width), width)
		end
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

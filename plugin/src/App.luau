--!strict
-- Shell: header (logo + live status), tab bar, animated view area, toasts and modal overlay.
-- Owns shared state (registry, settings, per-view UI state, last server check) and re-renders
-- the active view when the place changes.
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")

local Lint = require(script.Parent.Lint)
local Registry = require(script.Parent.Registry)
local Settings = require(script.Parent.Settings)
local Studio = require(script.Parent.Studio)
local Tagging = require(script.Parent.Tagging)
local Theme = require(script.Parent.Theme)
local UI = require(script.Parent.UI)

export type View = {
	id: string,
	title: string,
	-- Shown in the tab bar; other views open from inside a screen and get a "Voltar" link.
	nav: boolean?,
	-- Re-render triggers this view cares about.
	watches: { selection: boolean?, tags: boolean?, events: boolean? },
	render: (app: App, container: Frame) -> (),
}

export type ToastAction = { text: string, onClick: () -> () }

-- Last answer of the server about this game (via the connection-test code saved in Ajustes).
export type EventsCheck = {
	at: number,
	ok: boolean,
	message: string,
	gameName: string?,
	matches: boolean?,
	lastEventAt: number?,
}

export type App = {
	plugin: Plugin,
	widget: DockWidgetPluginGui,
	settings: Settings.Store,
	registry: Registry.Registry,
	registryNotes: { string },
	registryExists: boolean,
	tab: string,
	-- Where "Voltar" goes from a view outside the tab bar.
	back: string?,
	state: { [string]: any },
	events: EventsCheck?,
	checking: boolean,
	highlighter: Tagging.Highlighter,
	views: { View },
	render: (self: App) -> (),
	setTab: (self: App, id: string, back: string?) -> (),
	reloadRegistry: (self: App) -> (),
	saveRegistry: (self: App, registry: Registry.Registry, label: string, extra: (() -> ())?) -> string?,
	toast: (self: App, message: string, kind: ("info" | "success" | "warning" | "error")?, action: ToastAction?) -> (),
	undo: (self: App) -> (),
	testCode: (self: App) -> string?,
	setTestCode: (self: App, code: string?) -> (),
	checkEvents: (self: App) -> (),
	usages: (self: App, force: boolean?) -> { Lint.ScriptUsage },
	split: (self: App, container: Frame, leftWidth: number?) -> (Frame, Frame),
	destroy: (self: App) -> (),
}

local App = {}

local USAGE_CACHE_SECONDS = 5
local HEADER_HEIGHT = 52
local TABS_HEIGHT = 38
local EVENTS_POLL_SECONDS = 12
local PLUGIN_VERSION = "0.3.0"

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
		back = nil,
		state = {},
		events = nil,
		checking = false,
		views = views,
	} :: App

	local connections: { RBXScriptConnection } = {}
	local cleanups: { () -> () } = {}
	local root: Frame? = nil
	local content: CanvasGroup? = nil
	local toastLayer: Frame? = nil
	local headerStatus: Frame? = nil
	local toastToken = 0
	local usageCache: { Lint.ScriptUsage }? = nil
	local usageAt = 0
	local lastSerialized: string? = nil
	local renderQueued = false
	local registryConnection: RBXScriptConnection? = nil
	local destroyed = false

	self.highlighter = Tagging.highlighter(Theme.ACCENT)

	local function viewById(id: string): View?
		for _, view in views do
			if view.id == id then
				return view
			end
		end
		return nil
	end

	local function currentView(): View
		return viewById(self.tab) or views[1]
	end

	-- Header status chips -----------------------------------------------------------------------

	local function chip(text: string, state: UI.StatusState, onClick: (() -> ())?): any
		local p = UI.palette
		local color = UI.stateColor(state)
		local button = UI.new(if onClick then "TextButton" else "Frame", {
			BackgroundColor3 = color,
			BackgroundTransparency = 0.88,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
		}, {
			UI.new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.fromOffset(7, 7) }, {
				UI.corner(4),
			}),
			UI.label(text, { size = 12, font = Theme.FONT_MEDIUM, color = p.text, autoX = true, height = 24 }),
		})
		if onClick then
			button.AutoButtonColor = false
			button.Text = ""
			button.Activated:Connect(onClick)
			button.MouseEnter:Connect(function()
				UI.tween(button, { BackgroundTransparency = 0.75 }, 0.1)
			end)
			button.MouseLeave:Connect(function()
				UI.tween(button, { BackgroundTransparency = 0.88 }, 0.15)
			end)
		end
		UI.hlist(6).Parent = button
		UI.corner(12).Parent = button
		UI.padding(0, 10, 0, 9).Parent = button
		return button
	end

	local function updateHeaderStatus()
		local holder = headerStatus
		if not holder then
			return
		end
		UI.clear(holder)
		local events = self.events
		local sdk = Studio.sdkModule()
		if not sdk then
			chip("Instale o SDK", "warn", function()
				self:setTab("home")
			end).Parent = holder
			return
		end
		local age = if events and events.lastEventAt then os.time() - events.lastEventAt else nil
		if age and age < 120 then
			chip("Eventos chegando", "busy", function()
				self:setTab("home")
			end).Parent = holder
		else
			chip("SDK pronto", "ok", function()
				self:setTab("home")
			end).Parent = holder
		end
	end

	-- View rendering ------------------------------------------------------------------------------

	local function renderView(animate: boolean?)
		local container = content
		if not container then
			return
		end
		UI.clear(container)
		local view = currentView()
		local frame = UI.new("Frame", {
			Name = view.id,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Parent = container,
		})
		local body = frame
		if not view.nav then
			-- Views outside the tab bar: "Voltar" strip on top.
			local backId = self.back or "home"
			local backView = viewById(backId)
			local strip = UI.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 32),
				Parent = frame,
			}, {
				UI.link(`‹  Voltar para {if backView then backView.title else "Início"}`, function()
					self:setTab(backId)
				end),
				UI.label(view.title, {
					font = Theme.FONT_BOLD,
					size = 13,
					color = UI.palette.subText,
					autoX = true,
					height = 22,
				}),
			})
			UI.hlist(12).Parent = strip
			UI.padding(6, 14, 4, 14).Parent = strip
			body = UI.new("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 32),
				Size = UDim2.new(1, 0, 1, -32),
				Parent = frame,
			})
		end
		local ok, err = pcall(view.render :: any, self, body)
		if not ok then
			UI.clear(body)
			local message = UI.notice(`Algo deu errado ao desenhar esta tela: {err}`, "danger")
			message.Parent = body
			warn(`[RoMetrics plugin] {err}`)
		end
		if animate then
			container.GroupTransparency = 1
			frame.Position = UDim2.fromOffset(0, 8)
			UI.tween(container, { GroupTransparency = 0 }, 0.2)
			UI.tween(frame, { Position = UDim2.fromOffset(0, 0) }, 0.25)
		end
		updateHeaderStatus()
	end

	-- Shell ---------------------------------------------------------------------------------------

	local function buildTabs(): Frame
		local p = UI.palette
		local bar = UI.new("Frame", {
			Name = "Tabs",
			BackgroundColor3 = p.panel,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, HEADER_HEIGHT),
			Size = UDim2.new(1, 0, 0, TABS_HEIGHT),
		})
		local list = UI.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Parent = bar,
		})
		UI.hlist(4, Enum.VerticalAlignment.Bottom).Parent = list
		UI.padding(0, 10, 0, 10).Parent = list
		local underline = UI.new("Frame", {
			Name = "Underline",
			BackgroundColor3 = p.accent,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromOffset(0, 3),
			ZIndex = 3,
			Parent = bar,
		}, { UI.corner(2) })
		UI.new("Frame", {
			BackgroundColor3 = p.border,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 1),
			Parent = bar,
		})
		local activeId = if currentView().nav then self.tab else (self.back or "home")
		local activeButton: TextButton? = nil
		for index, view in views do
			if not view.nav then
				continue
			end
			local active = view.id == activeId
			local button = UI.new("TextButton", {
				Name = view.id,
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				Text = view.title,
				FontFace = if active then Theme.FONT_BOLD else Theme.FONT_MEDIUM,
				TextSize = 14,
				TextColor3 = if active then p.text else p.subText,
				Size = UDim2.fromScale(0, 1),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = index,
				Parent = list,
			})
			UI.padding(0, 10, 0, 10).Parent = button
			if active then
				activeButton = button
			else
				button.MouseEnter:Connect(function()
					UI.tween(button, { TextColor3 = p.text }, 0.1)
				end)
				button.MouseLeave:Connect(function()
					UI.tween(button, { TextColor3 = p.subText }, 0.15)
				end)
			end
			button.Activated:Connect(function()
				if self.tab ~= view.id then
					self:setTab(view.id)
				end
			end)
		end
		-- Slide the underline from the previous tab to the active one. Auto-sized tabs get their final
		-- size a frame or two later, so follow the tab's position/size until it settles.
		local previous = self.state.__underline
		if previous then
			underline.Position = UDim2.new(0, previous.x, 1, 0)
			underline.Size = UDim2.fromOffset(previous.width, 3)
		end
		local target = activeButton
		if target then
			local function follow()
				if not target.Parent or bar.AbsoluteSize.X == 0 then
					return
				end
				local x = target.AbsolutePosition.X - bar.AbsolutePosition.X + 10
				local width = math.max(0, target.AbsoluteSize.X - 20)
				UI.tween(underline, { Position = UDim2.new(0, x, 1, 0), Size = UDim2.fromOffset(width, 3) }, 0.25)
				self.state.__underline = { x = x, width = width }
			end
			target:GetPropertyChangedSignal("AbsolutePosition"):Connect(follow)
			target:GetPropertyChangedSignal("AbsoluteSize"):Connect(follow)
			task.defer(follow)
		end
		return bar
	end

	local function buildHeader(): Frame
		local p = UI.palette
		local brand = UI.row(10, {
			UI.logo(28),
			UI.column(0, {
				UI.label("RoMetrics", { font = Theme.FONT_BOLD, size = 16, height = 20 }),
				UI.label("Analytics do seu jogo", { size = 12, color = p.dimText, height = 15 }),
			}, { Size = UDim2.fromOffset(160, 0) }),
		}, { Size = UDim2.new(1, -200, 1, 0) })
		local status = UI.new("Frame", {
			Name = "Status",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 200, 1, 0),
		})
		local layout = UI.hlist(6, Enum.VerticalAlignment.Center)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		layout.Parent = status
		headerStatus = status
		local header = UI.new("Frame", {
			Name = "Header",
			BackgroundColor3 = p.panel,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
		}, { brand, status })
		UI.padding(0, 14, 0, 14).Parent = header
		return header
	end

	local function buildShell(animate: boolean?)
		if root then
			root:Destroy()
		end
		UI.setPalette(Theme.current())
		local p = UI.palette

		local body = UI.new("CanvasGroup", {
			Name = "Content",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, HEADER_HEIGHT + TABS_HEIGHT),
			Size = UDim2.new(1, 0, 1, -HEADER_HEIGHT - TABS_HEIGHT),
		})
		content = body

		local toasts = UI.new("Frame", {
			Name = "Toasts",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Size = UDim2.new(1, -24, 0, 0),
			ZIndex = 40,
		})
		toastLayer = toasts

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
		}, { buildHeader(), buildTabs(), body, toasts, overlay })
		newRoot.Parent = widget
		root = newRoot
		renderView(animate)
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
			if not destroyed then
				renderView(false)
			end
		end)
	end

	function self.render(_: App)
		buildShell(false)
	end

	function self.setTab(_: App, id: string, back: string?)
		local from = self.tab
		self.tab = id
		local view = viewById(id)
		if view and view.nav then
			settings:set("lastTab", id)
			self.back = nil
		else
			self.back = back or (if viewById(from) and (viewById(from) :: View).nav then from else self.back)
		end
		buildShell(true)
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
			self:toast(`Não deu para salvar: {err}`, "error")
			return err
		end
		lastSerialized = source
		self.registry = registry
		self.registryNotes = {}
		self.registryExists = true
		watchRegistryModule()
		self:toast(`Salvo: {label}`, "success", {
			text = "Desfazer",
			onClick = function()
				self:undo()
			end,
		})
		queueRender()
		return nil
	end

	function self.undo(_: App)
		local ok = pcall(function()
			ChangeHistoryService:Undo()
		end)
		self:toast(if ok then "Desfeito." else "Use Ctrl+Z para desfazer.", "info")
		usageCache = nil
		queueRender()
	end

	function self.toast(_: App, message: string, kind, action: ToastAction?)
		local layer = toastLayer
		if not layer then
			return
		end
		local p = UI.palette
		UI.clear(layer)
		local color = if kind == "error"
			then p.danger
			elseif kind == "warning" then p.warning
			elseif kind == "success" then p.success
			else p.accent
		local glyph = if kind == "error" then "!" elseif kind == "warning" then "!" elseif kind == "success" then "✓" else "i"
		local text = UI.label(message, { wrap = true, size = 13, color = p.text })
		text.Size = UDim2.fromScale(0, 0)
		text.AutomaticSize = Enum.AutomaticSize.Y
		UI.flex().Parent = text
		local children: { any } = { UI.icon(glyph, color, 24), text }
		if action then
			table.insert(
				children,
				UI.button(action.text, {
					variant = "ghost",
					onClick = function()
						UI.clear(layer)
						action.onClick()
					end,
				})
			)
		end
		local card = UI.card(children, { horizontal = true, gap = 10, padding = 10, stroke = color:Lerp(p.border, 0.5) })
		card.AnchorPoint = Vector2.new(0, 1)
		card.Position = UDim2.new(0, 0, 1, 40)
		card.BackgroundTransparency = 0
		UI.new("UISizeConstraint", { MaxSize = Vector2.new(520, math.huge), Parent = card })
		card.Parent = layer
		UI.tween(card, { Position = UDim2.fromScale(0, 1) }, 0.25, Enum.EasingStyle.Back)
		toastToken += 1
		local token = toastToken
		task.delay(if action then 8 else 4, function()
			if token == toastToken and card.Parent then
				local tween = UI.tween(card, { Position = UDim2.new(0, 0, 1, 80) }, 0.2)
				if tween then
					tween.Completed:Wait()
				end
				if token == toastToken then
					card:Destroy()
				end
			end
		end)
	end

	local codeKey = `RoMetrics_testCode_{game.PlaceId}`

	function self.testCode(_: App): string?
		local ok, code = pcall(function()
			return plugin:GetSetting(codeKey)
		end)
		return if ok and type(code) == "string" and code ~= "" then code else nil
	end

	function self.setTestCode(_: App, code: string?)
		pcall(function()
			plugin:SetSetting(codeKey, code)
		end)
	end

	-- Asks the server when it last received an event from this game. Yields; never throws.
	function self.checkEvents(_: App)
		local code = self:testCode()
		if not code or self.checking then
			return
		end
		self.checking = true
		local endpoint = settings:get("endpoint")
		local ok, message, gameName, matches, lastEventAt =
			Studio.reportConnectionTest(endpoint, code, Studio.placeReport(endpoint, PLUGIN_VERSION))
		self.checking = false
		self.events = {
			at = os.time(),
			ok = ok,
			message = message,
			gameName = gameName,
			matches = matches,
			lastEventAt = lastEventAt,
		}
		if not ok and string.find(message, "expirado", 1, true) then
			self:setTestCode(nil)
		end
		if widget.Enabled and not destroyed then
			if currentView().watches.events then
				queueRender()
			else
				updateHeaderStatus()
			end
		end
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
		destroyed = true
		for _, connection in connections do
			connection:Disconnect()
		end
		for _, cleanup in cleanups do
			cleanup()
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
	table.insert(cleanups, Theme.onChanged(function()
		buildShell(false)
	end))
	table.insert(cleanups, Studio.watchEditor(function()
		if widget.Enabled and currentView().watches.cursor then
			queueRender()
		end
	end))

	-- "Eventos chegando": while the panel is open, ask the server every few seconds (only once a
	-- connection-test code was saved in Ajustes; the code expires after 15 min).
	task.spawn(function()
		while not destroyed do
			if widget.Enabled and self:testCode() then
				pcall(self.checkEvents, self)
			end
			task.wait(EVENTS_POLL_SECONDS)
		end
	end)

	self.highlighter:setEnabled(settings:get("highlight"))
	local registry, notes, exists = Studio.loadRegistry()
	self.registry = registry
	self.registryNotes = notes
	self.registryExists = exists
	local module = Studio.registryModule()
	lastSerialized = if module then Studio.getSource(module) else nil
	watchRegistryModule()
	if not viewById(self.tab) or not (viewById(self.tab) :: View).nav then
		self.tab = "home"
	end
	buildShell(true)
	return self
end

return App

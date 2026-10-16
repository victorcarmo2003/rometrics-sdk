--!strict
--[[
	RoMetrics SDK — public API. Server-only.

	local RoMetrics = require(path.to.RoMetrics)
	RoMetrics.init({ key = HttpService:GetSecret("rometrics_key") })

	Every public call is wrapped so the SDK never throws into game code.
]]

local RunService = game:GetService("RunService")

local Types = require(script.Types)
local Config = require(script.Config)
local Transport = require(script.Transport)
local Queue = require(script.Queue)
local Server = require(script.Server)
local Session = require(script.Session)
local Purchases = require(script.Purchases)
local Analytics = require(script.Analytics)
local ClientBridge = require(script.Client.Bridge)
local Tags = require(script.Tags)
local Log = require(script.Util.Log)

export type Options = Types.Options

local RoMetrics = {}
RoMetrics.VERSION = "0.3.1"

type State = {
	config: Types.Config,
	queue: Types.Queue,
	sessions: Types.SessionTracker,
	analytics: Analytics.Analytics,
}
local state: State? = nil

local function safe<T...>(label: string, fn: (T...) -> ())
	return function(...: T...)
		local ok, err = pcall(fn, ...)
		if not ok then
			Log.warn(`{label} failed: {err}`)
		end
	end
end

function RoMetrics.init(options: Types.Options)
	if state then
		Log.warn("init called twice; ignoring")
		return
	end
	if not RunService:IsServer() then
		Log.warn("RoMetrics must be initialized on the server")
		return
	end
	local ok, err = pcall(function()
		local config = Config.resolve(options, RoMetrics.VERSION)
		Log.setDebug(config.debug)
		if RunService:IsStudio() and not config.enabledInStudio then
			Log.info("disabled in Studio (set enabledInStudio = true to send)")
			return
		end
		local transport = Transport.new(config)
		local queue = Queue.new(config, transport)
		local sessions = Session.start(config, queue)
		Server.start(config, queue)
		Purchases.start(config, queue, sessions)
		ClientBridge.start(config, queue, sessions)
		state = {
			config = config,
			queue = queue,
			sessions = sessions,
			analytics = Analytics.new(config, queue, sessions),
		}
		local analytics = (state :: State).analytics
		Tags.start(config, sessions, function(player, name, value, props)
			if player then
				analytics:logCustomEvent(player, name, value, props)
			else
				analytics:track(name, { value = value, props = props })
			end
		end)
		Log.info(`initialized v{RoMetrics.VERSION}`)
	end)
	if not ok then
		Log.warn(`init failed: {err}`)
	end
end

-- Wraps MarketplaceService.ProcessReceipt. Works even if init was not called
-- (purchases are then simply not tracked). The game's handler result is always preserved.
-- ProcessReceipt has a single owner (the last assignment wins): wrap the callback the game
-- already assigns instead of adding a second one.
function RoMetrics.wrapProcessReceipt(handler: (receiptInfo: { [string]: any }) -> Enum.ProductPurchaseDecision)
	return Purchases.wrapProcessReceipt(handler)
end

-- Records a granted developer product receipt from a ProcessReceipt the game owns
-- (call it right before returning PurchaseGranted). Alternative to wrapProcessReceipt.
function RoMetrics.trackReceipt(receiptInfo: { [string]: any })
	safe("trackReceipt", Purchases.trackReceipt)(receiptInfo)
end

-- AnalyticsService-compatible API (same argument order as the native service).

function RoMetrics.LogCustomEvent(_self: any, player: Player, eventName: string, value: number?, customFields: { [string]: any }?)
	safe("LogCustomEvent", function()
		if state then
			state.analytics:logCustomEvent(player, eventName, value, customFields)
		end
	end)()
end

function RoMetrics.LogEconomyEvent(
	_self: any,
	player: Player,
	flowType: Enum.AnalyticsEconomyFlowType,
	currencyType: string,
	amount: number,
	endingBalance: number,
	transactionType: string,
	itemSku: string?,
	customFields: { [string]: any }?
)
	safe("LogEconomyEvent", function()
		if state then
			state.analytics:logEconomyEvent(player, flowType, currencyType, amount, endingBalance, transactionType, itemSku, customFields)
		end
	end)()
end

function RoMetrics.LogFunnelStepEvent(
	_self: any,
	player: Player,
	funnelName: string,
	funnelSessionId: string?,
	step: number,
	stepName: string?,
	customFields: { [string]: any }?
)
	safe("LogFunnelStepEvent", function()
		if state then
			state.analytics:logFunnelStepEvent(player, funnelName, funnelSessionId, step, stepName, customFields)
		end
	end)()
end

function RoMetrics.LogOnboardingFunnelStepEvent(_self: any, player: Player, step: number, stepName: string?, customFields: { [string]: any }?)
	safe("LogOnboardingFunnelStepEvent", function()
		if state then
			state.analytics:logOnboardingFunnelStepEvent(player, step, stepName, customFields)
		end
	end)()
end

function RoMetrics.LogProgressionEvent(
	_self: any,
	player: Player,
	progressionPathName: string,
	status: Enum.AnalyticsProgressionType,
	level: number,
	levelName: string?,
	customFields: { [string]: any }?
)
	safe("LogProgressionEvent", function()
		if state then
			state.analytics:logProgressionEvent(player, progressionPathName, status, level, levelName, customFields)
		end
	end)()
end

-- Free-form event, optionally without a player.
function RoMetrics.track(_self: any, eventName: string, opts: { player: Player?, value: number?, props: { [string]: any }? }?)
	safe("track", function()
		if state then
			state.analytics:track(eventName, opts)
		end
	end)()
end

function RoMetrics.flush(_self: any)
	if state then
		state.queue:flush()
	end
end

return RoMetrics

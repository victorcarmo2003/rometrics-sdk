--!strict
--[[
	AnalyticsService-compatible logging.

	Each call validates/sanitizes its input, builds a wire event (RoMetrics ingest format)
	and pushes it to the queue. Invalid calls are dropped with a warning; nothing throws.

	* Names (event, funnel, progression path, currency) must match `^[A-Za-z0-9_.:-]{1,64}$`.
	  Other characters are replaced by `_` and the result is cut to 64 chars; empty names are dropped.
	* customFields/props are flattened to primitive values (string/number/boolean; other values are
	  converted with `tostring`) and capped at ~2 KB of JSON; keys beyond the cap are dropped
	  (sorted order) and `_truncated = true` is added.
	* Onboarding steps are funnel events named "Onboarding" with `onboarding = true`.
	* `forwardToRobloxAnalytics = true` also calls the native AnalyticsService with the original
	  arguments (in pcall). Native customFields only accept the `Enum.AnalyticsCustomFieldKeys`
	  names; use those keys if you rely on the native dashboard. `track` without a player is never
	  forwarded (the native API requires a player).
	* Player events need a live session (userId + sessionId are mandatory on the wire); calls for
	  players without a session are dropped with a debug log. Custom events without a session are
	  sent with userId only.
]]

local Types = require(script.Parent.Types)
local Log = require(script.Parent.Util.Log)
local Uuid = require(script.Parent.Util.Uuid)
local Clock = require(script.Parent.Util.Clock)
local UserIdUtil = require(script.Parent.Util.UserId)

export type Analytics = {
	logCustomEvent: (
		self: Analytics,
		player: Player,
		eventName: string,
		value: number?,
		customFields: { [string]: any }?
	) -> (),
	logEconomyEvent: (
		self: Analytics,
		player: Player,
		flowType: Enum.AnalyticsEconomyFlowType,
		currencyType: string,
		amount: number,
		endingBalance: number,
		transactionType: string,
		itemSku: string?,
		customFields: { [string]: any }?
	) -> (),
	logFunnelStepEvent: (
		self: Analytics,
		player: Player,
		funnelName: string,
		funnelSessionId: string?,
		step: number,
		stepName: string?,
		customFields: { [string]: any }?
	) -> (),
	logOnboardingFunnelStepEvent: (
		self: Analytics,
		player: Player,
		step: number,
		stepName: string?,
		customFields: { [string]: any }?
	) -> (),
	logProgressionEvent: (
		self: Analytics,
		player: Player,
		progressionPathName: string,
		status: Enum.AnalyticsProgressionType,
		level: number,
		levelName: string?,
		customFields: { [string]: any }?
	) -> (),
	track: (
		self: Analytics,
		eventName: string,
		opts: { player: Player?, value: number?, props: { [string]: any }? }?
	) -> (),
}

export type Deps = {
	-- Native AnalyticsService (or a fake in tests).
	analyticsService: any,
}

local MAX_NAME = 64
local MAX_PROPS_BYTES = 2000 -- ingest limit is 2048 bytes; keep headroom for estimation error
local MAX_PROP_KEY = 64
local MAX_PROP_STRING = 256
local ONBOARDING_FUNNEL = "Onboarding"

local Analytics = {}

-- Pure helpers, exported for unit tests.

function Analytics.sanitizeName(name: unknown): string?
	if type(name) ~= "string" then
		return nil
	end
	local cleaned = string.gsub(name, "[^%w_%.:%-]", "_")
	cleaned = string.sub(cleaned, 1, MAX_NAME)
	if cleaned == "" then
		return nil
	end
	return cleaned
end

local function isFinite(value: unknown): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function shortString(value: unknown, max: number): string?
	if type(value) ~= "string" or value == "" then
		return nil
	end
	return string.sub(value, 1, max)
end

-- Rough upper bound of the JSON size of a primitive value.
local function jsonSize(value: string | number | boolean): number
	if type(value) == "string" then
		local _, specials = string.gsub(value, '[%c"\\]', "")
		return #value + 2 + specials * 5
	elseif type(value) == "number" then
		return #string.format("%.17g", value)
	end
	return if value then 4 else 5
end

-- Flattens to primitives and caps the encoded size. Returns nil for empty/invalid input.
function Analytics.sanitizeProps(props: unknown): { [string]: any }?
	if type(props) ~= "table" then
		return nil
	end
	local entries: { { key: string, value: string | number | boolean } } = {}
	for rawKey, rawValue in props :: { [unknown]: unknown } do
		local key: string
		if type(rawKey) == "string" then
			key = rawKey
		elseif typeof(rawKey) == "EnumItem" then
			key = (rawKey :: EnumItem).Name
		else
			key = tostring(rawKey)
		end
		key = string.sub(key, 1, MAX_PROP_KEY)
		local value: string | number | boolean
		if type(rawValue) == "number" then
			if not isFinite(rawValue) then
				continue
			end
			value = rawValue :: number
		elseif type(rawValue) == "boolean" then
			value = rawValue :: boolean
		elseif type(rawValue) == "string" then
			value = string.sub(rawValue :: string, 1, MAX_PROP_STRING)
		elseif typeof(rawValue) == "EnumItem" then
			value = (rawValue :: EnumItem).Name
		else
			value = string.sub(tostring(rawValue), 1, MAX_PROP_STRING)
		end
		table.insert(entries, { key = key, value = value })
	end
	if #entries == 0 then
		return nil
	end
	table.sort(entries, function(a, b)
		return a.key < b.key
	end)
	local out: { [string]: any } = {}
	local size = 2 -- {}
	local truncated = false
	for _, entry in entries do
		local entrySize = jsonSize(entry.key) + 1 + jsonSize(entry.value) + 1
		if size + entrySize > MAX_PROPS_BYTES - 20 then
			truncated = true
			break
		end
		out[entry.key] = entry.value
		size += entrySize
	end
	if truncated then
		out._truncated = true
	end
	return out
end

local function enumName(value: unknown): string?
	if type(value) == "string" then
		return value
	end
	if typeof(value) == "EnumItem" then
		return (value :: EnumItem).Name
	end
	if type(value) == "table" and type((value :: any).Name) == "string" then
		return (value :: any).Name
	end
	return nil
end

function Analytics.mapFlowType(flowType: unknown): ("source" | "sink")?
	local name = enumName(flowType)
	local lower = if name then string.lower(name) else nil
	if lower == "source" then
		return "source"
	elseif lower == "sink" then
		return "sink"
	end
	return nil
end

function Analytics.mapProgressionStatus(status: unknown): ("start" | "fail" | "complete")?
	local name = enumName(status)
	local lower = if name then string.lower(name) else nil
	if lower == "start" then
		return "start"
	elseif lower == "fail" then
		return "fail"
	elseif lower == "complete" then
		return "complete"
	end
	return nil
end

local function userIdOf(player: unknown): number?
	if player == nil then
		return nil
	end
	local ok, userId = pcall(function()
		return (player :: any).UserId
	end)
	if ok then
		-- Same mapping as Session (Studio test players have negative ids).
		return UserIdUtil.normalize(userId)
	end
	return nil
end

function Analytics.new(config: Types.Config, queue: Types.Queue, sessions: Types.SessionTracker, deps: Deps?): Analytics
	local forward = config.forwardToRobloxAnalytics
	local native: any = nil
	if forward then
		native = if deps then deps.analyticsService else game:GetService("AnalyticsService")
	end

	local function forwardCall(method: string, ...: any)
		if not forward or native == nil then
			return
		end
		local args = table.pack(...)
		local ok, err = pcall(function()
			native[method](native, table.unpack(args, 1, args.n))
		end)
		if not ok then
			Log.debug(`AnalyticsService:{method} forward failed: {err}`)
		end
	end

	-- Resolves player + session for events that require both. Logs and returns nil when missing.
	local function playerSession(player: unknown, label: string): (number?, string?)
		local userId = userIdOf(player)
		if not userId then
			Log.warn(`{label}: invalid player`)
			return nil, nil
		end
		local session = sessions:get(player :: Player)
		if not session then
			Log.debug(`{label}: no session for {userId}, dropped`)
			return nil, nil
		end
		return userId, session.sessionId
	end

	local function push(event: Types.Event)
		queue:push(event)
	end

	local self = {}

	function self.logCustomEvent(
		_: any,
		player: Player,
		eventName: string,
		value: number?,
		customFields: { [string]: any }?
	)
		forwardCall("LogCustomEvent", player, eventName, value, customFields)
		local name = Analytics.sanitizeName(eventName)
		if not name then
			Log.warn(`LogCustomEvent: invalid event name {eventName}`)
			return
		end
		local userId = userIdOf(player)
		if not userId then
			Log.warn("LogCustomEvent: invalid player")
			return
		end
		local session = sessions:get(player)
		push({
			id = Uuid(),
			type = "custom",
			ts = Clock(),
			userId = userId,
			sessionId = if session then session.sessionId else nil,
			name = name,
			value = if isFinite(value) then value else nil,
			data = Analytics.sanitizeProps(customFields),
		})
	end

	function self.logEconomyEvent(
		_: any,
		player: Player,
		flowType: Enum.AnalyticsEconomyFlowType,
		currencyType: string,
		amount: number,
		endingBalance: number,
		transactionType: string,
		itemSku: string?,
		customFields: { [string]: any }?
	)
		forwardCall(
			"LogEconomyEvent",
			player,
			flowType,
			currencyType,
			amount,
			endingBalance,
			transactionType,
			itemSku,
			customFields
		)
		local flow = Analytics.mapFlowType(flowType)
		local currency = Analytics.sanitizeName(currencyType)
		if not flow or not currency or not isFinite(amount) then
			Log.warn("LogEconomyEvent: invalid flowType, currencyType or amount")
			return
		end
		local userId, sessionId = playerSession(player, "LogEconomyEvent")
		if not userId then
			return
		end
		local data: { [string]: any } = {
			flow = flow,
			currency = currency,
			amount = amount,
			transactionType = shortString(transactionType, MAX_NAME) or "",
		}
		if isFinite(endingBalance) then
			data.endingBalance = endingBalance
		end
		data.itemSku = shortString(itemSku, MAX_NAME)
		data.customFields = Analytics.sanitizeProps(customFields)
		push({ id = Uuid(), type = "economy", ts = Clock(), userId = userId, sessionId = sessionId, data = data })
	end

	local function funnel(
		label: string,
		player: Player,
		funnelName: string,
		funnelSessionId: string?,
		step: number,
		stepName: string?,
		customFields: { [string]: any }?,
		onboarding: boolean
	)
		local name = Analytics.sanitizeName(funnelName)
		if not name then
			Log.warn(`{label}: invalid funnel name {funnelName}`)
			return
		end
		if not isFinite(step) or step < 1 then
			Log.warn(`{label}: step must be >= 1`)
			return
		end
		local userId, sessionId = playerSession(player, label)
		if not userId then
			return
		end
		local data: { [string]: any } = {
			step = math.floor(step),
			funnelSessionId = shortString(funnelSessionId, MAX_NAME),
			stepName = shortString(stepName, MAX_NAME),
			customFields = Analytics.sanitizeProps(customFields),
		}
		if onboarding then
			data.onboarding = true
		end
		push({
			id = Uuid(),
			type = "funnel",
			ts = Clock(),
			userId = userId,
			sessionId = sessionId,
			name = name,
			data = data,
		})
	end

	function self.logFunnelStepEvent(
		_: any,
		player: Player,
		funnelName: string,
		funnelSessionId: string?,
		step: number,
		stepName: string?,
		customFields: { [string]: any }?
	)
		forwardCall("LogFunnelStepEvent", player, funnelName, funnelSessionId, step, stepName, customFields)
		funnel("LogFunnelStepEvent", player, funnelName, funnelSessionId, step, stepName, customFields, false)
	end

	function self.logOnboardingFunnelStepEvent(
		_: any,
		player: Player,
		step: number,
		stepName: string?,
		customFields: { [string]: any }?
	)
		forwardCall("LogOnboardingFunnelStepEvent", player, step, stepName, customFields)
		funnel("LogOnboardingFunnelStepEvent", player, ONBOARDING_FUNNEL, nil, step, stepName, customFields, true)
	end

	function self.logProgressionEvent(
		_: any,
		player: Player,
		progressionPathName: string,
		status: Enum.AnalyticsProgressionType,
		level: number,
		levelName: string?,
		customFields: { [string]: any }?
	)
		forwardCall("LogProgressionEvent", player, progressionPathName, status, level, levelName, customFields)
		local name = Analytics.sanitizeName(progressionPathName)
		local mapped = Analytics.mapProgressionStatus(status)
		if not name or not mapped or not isFinite(level) then
			Log.warn("LogProgressionEvent: invalid path name, status or level")
			return
		end
		local userId, sessionId = playerSession(player, "LogProgressionEvent")
		if not userId then
			return
		end
		push({
			id = Uuid(),
			type = "progression",
			ts = Clock(),
			userId = userId,
			sessionId = sessionId,
			name = name,
			data = {
				status = mapped,
				level = math.floor(level),
				levelName = shortString(levelName, MAX_NAME),
				customFields = Analytics.sanitizeProps(customFields),
			},
		})
	end

	function self.track(
		_: any,
		eventName: string,
		opts: { player: Player?, value: number?, props: { [string]: any }? }?
	)
		local player = if opts then opts.player else nil
		local value = if opts then opts.value else nil
		local props = if opts then opts.props else nil
		if player ~= nil then
			forwardCall("LogCustomEvent", player, eventName, value, props)
		end
		local name = Analytics.sanitizeName(eventName)
		if not name then
			Log.warn(`track: invalid event name {eventName}`)
			return
		end
		local userId: number? = nil
		local sessionId: string? = nil
		if player ~= nil then
			userId = userIdOf(player)
			local session = if userId then sessions:get(player) else nil
			sessionId = if session then session.sessionId else nil
		end
		push({
			id = Uuid(),
			type = "custom",
			ts = Clock(),
			userId = userId,
			sessionId = sessionId,
			name = name,
			value = if isFinite(value) then value else nil,
			data = Analytics.sanitizeProps(props),
		})
	end

	return (self :: any) :: Analytics
end

return Analytics

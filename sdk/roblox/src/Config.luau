--!strict
-- Validates options and applies defaults.
-- Invalid optional values fall back to defaults with a warning; only a missing key is fatal.
local Types = require(script.Parent.Types)
local Log = require(script.Parent.Util.Log)

local Config = {}

Config.DEFAULTS = table.freeze({
	endpoint = "https://ingest.rometrics.app",
	flushInterval = 10,
	maxBatchSize = 100,
	maxQueueSize = 5000,
	heartbeatInterval = 30,
})

-- Server-side limit: at most 500 events per batch.
Config.MAX_EVENTS_PER_BATCH = 500

local function numberOption(name: string, value: unknown, default: number, min: number, max: number): number
	if value == nil then
		return default
	end
	if typeof(value) ~= "number" or value ~= value then
		Log.warn(`option '{name}' must be a number; using default {default}`)
		return default
	end
	local n = value :: number
	if n < min or n > max then
		local clamped = math.clamp(n, min, max)
		Log.warn(`option '{name}' = {n} out of range [{min}, {max}]; using {clamped}`)
		return clamped
	end
	return n
end

local function booleanOption(name: string, value: unknown, default: boolean): boolean
	if value == nil then
		return default
	end
	if typeof(value) ~= "boolean" then
		Log.warn(`option '{name}' must be a boolean; using default {default}`)
		return default
	end
	return value :: boolean
end

local function endpointOption(value: unknown): string
	if value == nil then
		return Config.DEFAULTS.endpoint
	end
	if typeof(value) ~= "string" or not string.match(value :: string, "^https?://[^%s]+$") then
		Log.warn(`option 'endpoint' must be an http(s) URL; using default {Config.DEFAULTS.endpoint}`)
		return Config.DEFAULTS.endpoint
	end
	-- The ingestion key travels in a header: plain http is only allowed for loopback (local dev ingest).
	local url = value :: string
	if string.sub(url, 1, 7) == "http://" then
		local host = string.match(string.sub(url, 8), "^([^/:?#]+)") or ""
		host = string.lower(host)
		if host ~= "localhost" and host ~= "127.0.0.1" then
			Log.warn(`option 'endpoint' must use https (the key would be sent in clear text); using default {Config.DEFAULTS.endpoint}`)
			return Config.DEFAULTS.endpoint
		end
	end
	-- Reject credentials embedded in the URL (http://user@host).
	if string.find(string.match(url, "^https?://([^/]*)") or "", "@", 1, true) then
		Log.warn(`option 'endpoint' must not contain credentials; using default {Config.DEFAULTS.endpoint}`)
		return Config.DEFAULTS.endpoint
	end
	-- Strip trailing slashes so `{endpoint}/v1/batch` is well-formed.
	return (string.gsub(value :: string, "/+$", ""))
end

local function keyOption(value: unknown): string | Secret
	local kind = typeof(value)
	if kind == "Secret" then
		return value :: Secret
	end
	if kind == "string" then
		local key = value :: string
		if key == "" then
			error("RoMetrics: option 'key' is empty", 0)
		end
		return key
	end
	error("RoMetrics: option 'key' is required (HttpService:GetSecret(...) or a string in Studio)", 0)
end

-- Throws only when the key is missing/invalid (init wraps this in pcall).
function Config.resolve(options: Types.Options, sdkVersion: string): Types.Config
	if typeof(options) ~= "table" then
		error("RoMetrics: init options must be a table", 0)
	end
	local opts = (options :: any) :: { [string]: unknown }

	local maxBatchSize = math.floor(
		numberOption("maxBatchSize", opts.maxBatchSize, Config.DEFAULTS.maxBatchSize, 1, Config.MAX_EVENTS_PER_BATCH)
	)
	local maxQueueSize =
		math.floor(numberOption("maxQueueSize", opts.maxQueueSize, Config.DEFAULTS.maxQueueSize, 1, 100000))
	if maxQueueSize < maxBatchSize then
		Log.warn(`option 'maxQueueSize' ({maxQueueSize}) < maxBatchSize ({maxBatchSize}); using {maxBatchSize}`)
		maxQueueSize = maxBatchSize
	end

	return {
		key = keyOption(opts.key),
		endpoint = endpointOption(opts.endpoint),
		flushInterval = numberOption("flushInterval", opts.flushInterval, Config.DEFAULTS.flushInterval, 1, 300),
		maxBatchSize = maxBatchSize,
		maxQueueSize = maxQueueSize,
		heartbeatInterval = numberOption(
			"heartbeatInterval",
			opts.heartbeatInterval,
			Config.DEFAULTS.heartbeatInterval,
			5,
			60
		),
		forwardToRobloxAnalytics = booleanOption("forwardToRobloxAnalytics", opts.forwardToRobloxAnalytics, false),
		debug = booleanOption("debug", opts.debug, false),
		enabledInStudio = booleanOption("enabledInStudio", opts.enabledInStudio, false),
		sdkVersion = sdkVersion,
	}
end

return Config

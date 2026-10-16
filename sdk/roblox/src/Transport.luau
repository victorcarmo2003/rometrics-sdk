--!strict
-- HTTP POST {endpoint}/v1/batch with key header, gzip, status mapping.
--
-- Status mapping:
--   2xx                  -> "ok"
--   400, 413, other 4xx  -> "drop"   (bad batch; retrying would fail again)
--   401, 403             -> "fatal"  (invalid/revoked key or wrong universe)
--   408, 429, 5xx, error -> "retry"  (`retryAfter` holds the server hint in seconds, if any)
local HttpService = game:GetService("HttpService")

local Types = require(script.Parent.Types)
local Server = require(script.Parent.Server)
local Clock = require(script.Parent.Util.Clock)
local Log = require(script.Parent.Util.Log)

export type Status = "ok" | "drop" | "retry" | "fatal"

export type HttpRequest = {
	Url: string,
	Method: string,
	Headers: { [string]: any },
	Body: string,
	Compress: Enum.HttpCompression,
}

export type HttpResponse = {
	Success: boolean,
	StatusCode: number,
	StatusMessage: string?,
	Headers: { [string]: string }?,
	Body: string?,
}

-- Seams for unit tests. Production uses HttpService and Server.info().
export type Deps = {
	request: ((req: HttpRequest) -> HttpResponse)?,
	serverInfo: (() -> Types.ServerInfo)?,
	now: (() -> number)?,
}

-- Types.Transport plus the last retry-after hint, read by Queue after a "retry".
export type HttpTransport = Types.Transport & { retryAfter: number? }

local Transport = {}

Transport.KEY_HEADER = "x-rometrics-key"
Transport.SDK_NAME = "rometrics-luau"
-- Bodies smaller than this are sent uncompressed (gzip overhead isn't worth it).
Transport.GZIP_MIN_BYTES = 1024
-- Ingest bodyLimit is 1 MB (INGEST_LIMITS.maxBatchBytes); keep headroom. Measured before gzip.
Transport.MAX_BODY_BYTES = 900_000

-- RequestAsync error raised when "Allow HTTP Requests" is off. Pure; unit tested.
function Transport.isHttpDisabledError(message: string): boolean
	local lower = string.lower(message)
	return string.find(lower, "http requests are not enabled", 1, true) ~= nil
		or string.find(lower, "httpenabled", 1, true) ~= nil
end

-- Actionable warning for 401/403 (the SDK disables itself until the server restarts). Pure; unit tested.
function Transport.fatalMessage(statusCode: number, body: string?, universeId: number): string
	local text = body or ""
	local reason
	if string.find(text, "universe_mismatch", 1, true) then
		reason = `this key belongs to another game: register Universe ID {universeId} in the dashboard`
			.. " (Settings > Games) and create a key for it"
		if universeId == 0 then
			reason ..= "; unpublished places have Universe ID 0, publish the place first"
		end
	elseif statusCode == 401 then
		reason = "invalid or revoked key (check the secret/string passed as `key`)"
	else
		reason = `forbidden: {text}`
	end
	return `server refused the key ({statusCode}): {reason}. RoMetrics disabled until restart`
end

local function defaultRequest(req: HttpRequest): HttpResponse
	return HttpService:RequestAsync(req :: any) :: any
end

-- Parses a retry-after header (delta-seconds only; HTTP dates are ignored).
function Transport.parseRetryAfter(headers: { [string]: string }?): number?
	if not headers then
		return nil
	end
	for name, value in headers do
		if string.lower(name) == "retry-after" then
			local seconds = tonumber(value)
			if seconds and seconds >= 0 then
				return seconds
			end
			return nil
		end
	end
	return nil
end

function Transport.classify(statusCode: number): Status
	if statusCode >= 200 and statusCode < 300 then
		return "ok"
	elseif statusCode == 401 or statusCode == 403 then
		return "fatal"
	elseif statusCode == 408 or statusCode == 429 or statusCode >= 500 then
		return "retry"
	elseif statusCode >= 400 then
		return "drop"
	end
	-- 1xx/3xx: unexpected for this endpoint; try again later.
	return "retry"
end

function Transport.new(config: Types.Config, deps: Deps?): HttpTransport
	local request = (deps and deps.request) or defaultRequest
	local serverInfo = (deps and deps.serverInfo) or Server.info
	local now = (deps and deps.now) or Clock
	local url = `{config.endpoint}/v1/batch`

	local transport = {
		retryAfter = nil :: number?,
	}

	local warnedHttpDisabled = false

	local function sendBatch(events: { Types.Event }): Status
		local server = serverInfo()
		local encodeOk, body = pcall(HttpService.JSONEncode, HttpService, {
			sdk = { name = Transport.SDK_NAME, version = config.sdkVersion },
			server = server,
			sentAt = now(),
			events = events,
		})
		if not encodeOk then
			Log.warn(`dropping batch of {#events}: JSON encode failed ({body})`)
			return "drop"
		end

		-- The ingest rejects bodies over 1 MB with 413 (the whole batch would be lost): split instead.
		if #body > Transport.MAX_BODY_BYTES then
			if #events <= 1 then
				Log.warn(`dropping event of {#body} bytes: over the {Transport.MAX_BODY_BYTES}-byte limit`)
				return "drop"
			end
			local half = #events // 2
			local first: Status = sendBatch(table.move(events, 1, half, 1, {}))
			if first ~= "ok" and first ~= "drop" then
				-- Queue re-sends the whole batch; the ingest dedupes events by id.
				return first
			end
			local second: Status = sendBatch(table.move(events, half + 1, #events, 1, {}))
			if second ~= "ok" then
				return second
			end
			return first
		end

		local reqOk, res = pcall(request, {
			Url = url,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
				[Transport.KEY_HEADER] = config.key,
			},
			Body = body,
			Compress = if #body >= Transport.GZIP_MIN_BYTES
				then Enum.HttpCompression.Gzip
				else Enum.HttpCompression.None,
		})
		if not reqOk then
			local message = tostring(res)
			if Transport.isHttpDisabledError(message) then
				if not warnedHttpDisabled then
					warnedHttpDisabled = true
					Log.warn(
						"HTTP requests are disabled: enable File > Experience Settings > Security > Allow HTTP Requests"
					)
				end
			else
				Log.debug(`request failed: {message}`)
			end
			return "retry"
		end

		local response = res :: HttpResponse
		local status: Status = Transport.classify(response.StatusCode)
		if status == "ok" then
			Log.debug(`sent {#events} events ({response.StatusCode})`)
		elseif status == "retry" then
			transport.retryAfter = Transport.parseRetryAfter(response.Headers)
			Log.debug(`server returned {response.StatusCode}; will retry`)
		elseif status == "drop" then
			Log.warn(`server rejected batch of {#events} ({response.StatusCode}): {response.Body or ""}`)
		else
			Log.warn(Transport.fatalMessage(response.StatusCode, response.Body, server.universeId))
		end
		return status
	end

	function transport.send(_self: any, events: { Types.Event }): Status
		transport.retryAfter = nil

		-- JSONEncode turns an empty table into `[]`, which the ingest schema rejects for `data`.
		for _, event in events do
			if event.data and next(event.data) == nil then
				event.data = nil
			end
		end

		return sendBatch(events)
	end

	return (transport :: any) :: HttpTransport
end

return Transport

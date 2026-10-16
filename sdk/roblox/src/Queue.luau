--!strict
-- Buffer, periodic flush, backoff, circuit breaker.
--
-- - Ring buffer up to config.maxQueueSize; overflow drops the OLDEST events (counted in `dropped`).
-- - flush() is async (task.spawn) and only one drain runs at a time.
-- - Batches go out spaced by MIN_SEND_INTERVAL to stay under the ingest per-job limit (30 req/min).
-- - "retry": the batch goes back to the front; exponential backoff 2..60 s with jitter, honouring
--   retry-after. BREAKER_THRESHOLD consecutive failures open the breaker for BREAKER_OPEN_S.
--   The first failure of a streak and each breaker opening warn with the transport's `lastError`.
--   Retries happen on the next periodic tick after the backoff expires.
-- - "drop": batch discarded (counted in `dropped`). "fatal": queue disabled until restart.
-- - flushSync(timeout) is used by BindToClose: blocks, ignores the breaker, bigger batches.
local Types = require(script.Parent.Types)
local Log = require(script.Parent.Util.Log)

type Status = "ok" | "drop" | "retry" | "fatal"

-- Seams for unit tests. `now` is monotonic seconds.
export type Deps = {
	now: (() -> number)?,
	random: (() -> number)?,
	spawn: ((fn: () -> ()) -> ())?,
	wait: ((seconds: number) -> ())?,
	-- Starts the periodic flush loop (default true).
	autoStart: boolean?,
}

local Queue = {}

Queue.BACKOFF_MIN_S = 2
Queue.BACKOFF_MAX_S = 60
Queue.RETRY_AFTER_MAX_S = 300
Queue.BREAKER_THRESHOLD = 5
Queue.BREAKER_OPEN_S = 60
Queue.MIN_SEND_INTERVAL_S = 2
-- flushSync drains with bigger batches (ingest max is 500 events per batch).
Queue.SYNC_BATCH_SIZE = 500

-- Exponential backoff with +/-25% jitter, clamped to [BACKOFF_MIN_S, BACKOFF_MAX_S], then raised to
-- the server's retry-after (capped). Pure; unit tested.
function Queue.backoffDelay(failures: number, random: number, retryAfter: number?): number
	local base = Queue.BACKOFF_MIN_S * 2 ^ math.max(failures - 1, 0)
	local delay = math.clamp(base * (0.75 + 0.5 * random), Queue.BACKOFF_MIN_S, Queue.BACKOFF_MAX_S)
	if retryAfter then
		delay = math.max(delay, math.min(retryAfter, Queue.RETRY_AFTER_MAX_S))
	end
	return delay
end

function Queue.new(config: Types.Config, transport: Types.Transport, deps: Deps?): Types.Queue
	local now: () -> number = (deps and deps.now) or os.clock
	local random: () -> number = (deps and deps.random) or math.random
	local spawn: (fn: () -> ()) -> () = (deps and deps.spawn) or function(fn: () -> ())
		task.spawn(fn)
	end
	local wait: (seconds: number) -> () = (deps and deps.wait) or function(seconds: number)
		task.wait(seconds)
	end
	local autoStart = if deps and deps.autoStart ~= nil then deps.autoStart else true

	-- Ring buffer: live items are items[head..tail].
	local items: { [number]: Types.Event } = {}
	local head, tail = 1, 0

	local sent, dropped = 0, 0
	local failures = 0
	local nextAttemptAt = -math.huge
	local breakerUntil = -math.huge
	local lastSendAt = -math.huge
	local flushing = false
	local disabled = false
	local destroyed = false

	local function size(): number
		return tail - head + 1
	end

	local function trimOverflow()
		local over = size() - config.maxQueueSize
		if over <= 0 then
			return
		end
		for _ = 1, over do
			items[head] = nil
			head += 1
		end
		dropped += over
		Log.debug(`queue full; dropped {over} oldest events`)
	end

	local function takeBatch(n: number): { Types.Event }
		local batch = table.create(math.min(n, size()))
		for i = 1, math.min(n, size()) do
			batch[i] = items[head]
			items[head] = nil
			head += 1
		end
		return batch
	end

	local function requeueFront(batch: { Types.Event })
		for i = #batch, 1, -1 do
			head -= 1
			items[head] = batch[i]
		end
		trimOverflow()
	end

	local function clear(): number
		local n = size()
		table.clear(items)
		head, tail = 1, 0
		return n
	end

	local function disable()
		disabled = true
		dropped += clear()
	end

	-- Sends one batch and updates counters/backoff. Returns the transport status.
	local function sendOne(batchSize: number): Status
		local batch = takeBatch(batchSize)
		lastSendAt = now()
		local ok, result = pcall(transport.send, transport, batch)
		local status: Status = if ok then (result :: any) :: Status else "retry"

		if status == "ok" then
			sent += #batch
			failures = 0
			nextAttemptAt = -math.huge
		elseif status == "drop" then
			dropped += #batch
			failures = 0
			nextAttemptAt = -math.huge
		elseif status == "fatal" then
			dropped += #batch
			disable()
		else
			requeueFront(batch)
			failures += 1
			local retryAfter = (transport :: any).retryAfter
			local hint = if typeof(retryAfter) == "number" then retryAfter else nil
			local delay = Queue.backoffDelay(failures, random(), hint)
			nextAttemptAt = now() + delay
			local lastError = (transport :: any).lastError
			local reason = if not ok
				then `transport error: {result}`
				elseif typeof(lastError) == "string" then lastError
				else "unknown error"
			if failures >= Queue.BREAKER_THRESHOLD then
				breakerUntil = now() + Queue.BREAKER_OPEN_S
				Log.warn(`{failures} consecutive send failures ({reason}); pausing for {Queue.BREAKER_OPEN_S}s`)
			elseif failures == 1 then
				-- Always visible (not only with debug): a wrong endpoint would otherwise fail silently.
				Log.warn(`send failed: {reason}; retrying in {string.format("%.1f", delay)}s`)
			else
				Log.debug(`send failed ({failures}); retrying in {string.format("%.1f", delay)}s`)
			end
		end
		return status
	end

	local function canSend(): boolean
		local t = now()
		return not disabled and t >= nextAttemptAt and t >= breakerUntil
	end

	local function drain()
		while size() > 0 and canSend() do
			local gap = Queue.MIN_SEND_INTERVAL_S - (now() - lastSendAt)
			if gap > 0 then
				wait(gap)
				if disabled then
					return
				end
			end
			local status = sendOne(config.maxBatchSize)
			if status == "retry" or status == "fatal" then
				return
			end
		end
	end

	local queue = {}

	function queue.push(_self: any, event: Types.Event)
		if disabled then
			return
		end
		tail += 1
		items[tail] = event
		trimOverflow()
		if size() >= config.maxBatchSize then
			queue.flush(queue)
		end
	end

	function queue.flush(_self: any)
		if flushing or disabled or size() == 0 then
			return
		end
		flushing = true
		spawn(function()
			local ok, err = pcall(function()
				drain()
			end)
			flushing = false
			if not ok then
				Log.warn(`flush failed: {err}`)
			end
		end)
	end

	function queue.flushSync(_self: any, timeout: number)
		local deadline = now() + timeout
		-- Let an in-flight async drain finish first (one request at a time).
		while flushing and now() < deadline do
			wait(0.1)
		end
		if flushing then
			return
		end
		flushing = true
		local ok, err = pcall(function()
			while size() > 0 and not disabled and now() < deadline do
				local status = sendOne(Queue.SYNC_BATCH_SIZE)
				if status == "retry" then
					local remaining = deadline - now()
					if remaining <= 0 then
						break
					end
					wait(math.min(math.max(nextAttemptAt - now(), 0), remaining))
				end
			end
		end)
		flushing = false
		if not ok then
			Log.warn(`flushSync failed: {err}`)
		end
		if size() > 0 then
			Log.warn(`shutdown flush left {size()} events unsent`)
		end
	end

	function queue.stats(_self: any): { queued: number, dropped: number, sent: number }
		return { queued = size(), dropped = dropped, sent = sent }
	end

	function queue.destroy(_self: any)
		destroyed = true
	end

	if autoStart then
		spawn(function()
			while not destroyed and not disabled do
				wait(config.flushInterval)
				if destroyed then
					break
				end
				queue.flush(queue)
			end
		end)
	end

	return (queue :: any) :: Types.Queue
end

return Queue

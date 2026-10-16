--!strict
-- Test doubles for the SDK core: fake clock/scheduler and a scripted Transport.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.RoMetrics.Types)

local Fakes = {}

export type FakeClock = {
	t: number,
	now: () -> number,
	wait: (seconds: number) -> (),
	advance: (seconds: number) -> (),
}

function Fakes.clock(): FakeClock
	local clock = { t = 1000 } :: any
	clock.now = function(): number
		return clock.t
	end
	clock.wait = function(seconds: number)
		clock.t += seconds
	end
	clock.advance = function(seconds: number)
		clock.t += seconds
	end
	return clock :: FakeClock
end

export type FakeTransport = {
	calls: { { Types.Event } },
	-- Statuses returned in order; once exhausted, `default` is returned.
	script: { string },
	default: string,
	retryAfter: number?,
	throws: boolean,
	send: (self: FakeTransport, events: { Types.Event }) -> string,
}

function Fakes.transport(default: string?): FakeTransport
	local transport = {
		calls = {},
		script = {},
		default = default or "ok",
		retryAfter = nil,
		throws = false,
	} :: any
	function transport.send(self: any, events: { Types.Event }): string
		table.insert(self.calls, table.clone(events))
		if self.throws then
			error("boom")
		end
		local status = table.remove(self.script, 1)
		return status or self.default
	end
	return transport :: FakeTransport
end

function Fakes.config(overrides: { [string]: any }?): Types.Config
	local config: { [string]: any } = {
		key = "rmk_live_test",
		endpoint = "http://localhost:4100",
		flushInterval = 10,
		maxBatchSize = 3,
		maxQueueSize = 100,
		heartbeatInterval = 30,
		forwardToRobloxAnalytics = false,
		debug = false,
		enabledInStudio = true,
		sdkVersion = "0.0.0-test",
	}
	for k, v in (overrides or {}) :: { [string]: any } do
		config[k] = v
	end
	return config :: any
end

local counter = 0
function Fakes.event(name: string?): Types.Event
	counter += 1
	return { id = `evt-{counter}`, type = "custom", ts = counter, name = name or `e{counter}` }
end

-- Deterministic deps for Queue.new: synchronous spawn, fake time, jitter fixed at 0.5.
function Fakes.queueDeps(clock: FakeClock): { [string]: any }
	return {
		now = clock.now,
		wait = clock.wait,
		random = function()
			return 0.5
		end,
		spawn = function(fn: () -> ())
			fn()
		end,
		autoStart = false,
	}
end

return Fakes

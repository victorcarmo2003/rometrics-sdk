--!strict
-- Test doubles shared by the purchases/analytics specs (TestEZ-style).

local Fakes = {}

export type Signal = {
	Connect: (self: Signal, fn: (...any) -> ()) -> { Disconnect: (any) -> () },
	Fire: (self: Signal, ...any) -> (),
	count: (self: Signal) -> number,
}

function Fakes.signal(): Signal
	local handlers: { [number]: (...any) -> () } = {}
	local nextId = 0
	local signal = {}
	function signal.Connect(_: any, fn: (...any) -> ())
		nextId += 1
		local id = nextId
		handlers[id] = fn
		return {
			Disconnect = function()
				handlers[id] = nil
			end,
		}
	end
	function signal.Fire(_: any, ...: any)
		for _, fn in handlers do
			fn(...)
		end
	end
	function signal.count(_: any): number
		local n = 0
		for _ in handlers do
			n += 1
		end
		return n
	end
	return (signal :: any) :: Signal
end

function Fakes.config(overrides: { [string]: any }?): any
	local config: { [string]: any } = {
		key = "rmk_live_test",
		endpoint = "http://localhost:4100",
		flushInterval = 10,
		maxBatchSize = 100,
		maxQueueSize = 5000,
		heartbeatInterval = 30,
		forwardToRobloxAnalytics = false,
		debug = false,
		enabledInStudio = true,
		sdkVersion = "0.0.0-test",
	}
	if overrides then
		for k, v in overrides do
			config[k] = v
		end
	end
	return config
end

export type FakeQueue = {
	events: { any },
	push: (any, any) -> (),
	flush: (any) -> (),
	flushSync: (any, number) -> (),
	stats: (any) -> any,
	destroy: (any) -> (),
}

function Fakes.queue(): FakeQueue
	local q = { events = {} }
	function q.push(self: any, event: any)
		table.insert(self.events, event)
	end
	function q.flush(_: any) end
	function q.flushSync(_: any, _timeout: number) end
	function q.stats(self: any)
		return { queued = #self.events, dropped = 0, sent = 0 }
	end
	function q.destroy(_: any) end
	return q :: any
end

function Fakes.player(userId: number): any
	return { UserId = userId, Name = `Player{userId}`, Parent = {} }
end

export type FakeSessions = {
	byPlayer: { [any]: any },
	add: (any, any) -> any,
	get: (any, any) -> any,
	destroy: (any) -> (),
}

function Fakes.sessions(): FakeSessions
	local s = { byPlayer = {} }
	function s.add(self: any, player: any)
		local info = {
			sessionId = string.format("00000000-0000-4000-8000-%012d", player.UserId),
			userId = player.UserId,
			startedAt = 0,
		}
		self.byPlayer[player] = info
		return info
	end
	function s.get(self: any, player: any)
		return self.byPlayer[player]
	end
	function s.destroy(_: any) end
	return s :: any
end

function Fakes.players(list: { any }): any
	local players = { PlayerRemoving = Fakes.signal(), list = list }
	function players.GetPlayerByUserId(_: any, userId: number)
		for _, p in list do
			if p.UserId == userId then
				return p
			end
		end
		return nil
	end
	return players
end

-- products: { [id] = { Name, PriceInRobux } }; failures: number of calls that error first.
function Fakes.marketplace(products: { [number]: any }, failures: number?): any
	local mp = {
		PromptGamePassPurchaseFinished = Fakes.signal(),
		PromptProductPurchaseFinished = Fakes.signal(),
		calls = 0,
		failuresLeft = failures or 0,
	}
	function mp.GetProductInfo(self: any, id: number, _infoType: any)
		self.calls += 1
		if self.failuresLeft > 0 then
			self.failuresLeft -= 1
			error("HTTP 500")
		end
		local info = products[id]
		if not info then
			error("not found")
		end
		return info
	end
	return mp
end

function Fakes.analyticsService(): any
	local svc = { calls = {} }
	local function recorder(method: string)
		return function(self: any, ...: any)
			table.insert(self.calls, { method = method, args = table.pack(...) })
		end
	end
	svc.LogCustomEvent = recorder("LogCustomEvent")
	svc.LogEconomyEvent = recorder("LogEconomyEvent")
	svc.LogFunnelStepEvent = recorder("LogFunnelStepEvent")
	svc.LogOnboardingFunnelStepEvent = recorder("LogOnboardingFunnelStepEvent")
	svc.LogProgressionEvent = recorder("LogProgressionEvent")
	return svc
end

function Fakes.remoteEvent(name: string): any
	local remote = { Name = name, OnServerEvent = Fakes.signal() }
	function remote.IsA(_: any, className: string)
		return className == "RemoteEvent"
	end
	return remote
end

-- Container with FindFirstChild over a name->child map.
function Fakes.container(children: { [string]: any }): any
	local c = { children = children }
	function c.FindFirstChild(self: any, name: string)
		return self.children[name]
	end
	return c
end

return Fakes

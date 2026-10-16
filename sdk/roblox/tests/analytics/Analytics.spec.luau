--!strict
-- TestEZ-style spec for Analytics (AnalyticsService-compatible API).

local RoMetrics = script.Parent.Parent.Parent.RoMetrics
local Analytics = require(RoMetrics.Analytics) :: any
local Fakes = require(script.Parent.Parent.purchases.Fakes)

return function()
	local queue: any
	local sessions: any
	local player: any
	local native: any

	local function make(forward: boolean?): any
		queue = Fakes.queue()
		sessions = Fakes.sessions()
		player = Fakes.player(7)
		sessions:add(player)
		native = Fakes.analyticsService()
		return Analytics.new(
			Fakes.config({ forwardToRobloxAnalytics = forward == true }),
			queue,
			sessions,
			{ analyticsService = native }
		)
	end

	describe("sanitizeName", function()
		it("keeps valid names", function()
			expect(Analytics.sanitizeName("Boss.Killed:v2-x_1")).to.equal("Boss.Killed:v2-x_1")
		end)
		it("replaces invalid characters and truncates to 64", function()
			expect(Analytics.sanitizeName("Boss Killed!")).to.equal("Boss_Killed_")
			expect(#Analytics.sanitizeName(string.rep("a", 100))).to.equal(64)
		end)
		it("rejects empty and non-string names", function()
			expect(Analytics.sanitizeName("")).to.equal(nil)
			expect(Analytics.sanitizeName(nil)).to.equal(nil)
			expect(Analytics.sanitizeName(5)).to.equal(nil)
		end)
	end)

	describe("sanitizeProps", function()
		it("flattens to primitives", function()
			local props = Analytics.sanitizeProps({ a = 1, b = "x", c = true, d = { 1 }, e = 0 / 0 })
			expect(props.a).to.equal(1)
			expect(props.b).to.equal("x")
			expect(props.c).to.equal(true)
			expect(type(props.d)).to.equal("string")
			expect(props.e).to.equal(nil)
		end)
		it("caps the payload at ~2 KB", function()
			local big = {}
			for i = 1, 50 do
				big[string.format("k%02d", i)] = string.rep("x", 100)
			end
			local props = Analytics.sanitizeProps(big)
			expect(props._truncated).to.equal(true)
			local size = 0
			for k, v in props do
				size += #tostring(k) + #tostring(v) + 6
			end
			expect(size <= 2048).to.equal(true)
		end)
		it("returns nil for empty input", function()
			expect(Analytics.sanitizeProps({})).to.equal(nil)
			expect(Analytics.sanitizeProps(nil)).to.equal(nil)
		end)
	end)

	describe("enum mapping", function()
		it("maps economy flow types", function()
			expect(Analytics.mapFlowType(Enum.AnalyticsEconomyFlowType.Source)).to.equal("source")
			expect(Analytics.mapFlowType(Enum.AnalyticsEconomyFlowType.Sink)).to.equal("sink")
			expect(Analytics.mapFlowType("bogus")).to.equal(nil)
		end)
		it("maps progression status", function()
			expect(Analytics.mapProgressionStatus(Enum.AnalyticsProgressionType.Start)).to.equal("start")
			expect(Analytics.mapProgressionStatus(Enum.AnalyticsProgressionType.Fail)).to.equal("fail")
			expect(Analytics.mapProgressionStatus(Enum.AnalyticsProgressionType.Complete)).to.equal("complete")
		end)
	end)

	describe("events", function()
		it("logCustomEvent emits custom with session", function()
			local a = make()
			a:logCustomEvent(player, "BossKilled", 1, { boss = "Dragon" })
			local e = queue.events[1]
			expect(e.type).to.equal("custom")
			expect(e.name).to.equal("BossKilled")
			expect(e.value).to.equal(1)
			expect(e.userId).to.equal(7)
			expect(e.sessionId).to.equal(sessions:get(player).sessionId)
			expect(e.data.boss).to.equal("Dragon")
			expect(type(e.id)).to.equal("string")
			expect(type(e.ts)).to.equal("number")
		end)

		it("logEconomyEvent maps flow and keeps fields", function()
			local a = make()
			a:logEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Sink, "Coins", 100, 500, "Shop", "Sword")
			local e = queue.events[1]
			expect(e.type).to.equal("economy")
			expect(e.data.flow).to.equal("sink")
			expect(e.data.currency).to.equal("Coins")
			expect(e.data.amount).to.equal(100)
			expect(e.data.endingBalance).to.equal(500)
			expect(e.data.transactionType).to.equal("Shop")
			expect(e.data.itemSku).to.equal("Sword")
		end)

		it("drops economy events with invalid amount", function()
			local a = make()
			a:logEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Source, "Coins", 0 / 0, 0, "Quest")
			expect(#queue.events).to.equal(0)
		end)

		it("logFunnelStepEvent validates step", function()
			local a = make()
			a:logFunnelStepEvent(player, "Tutorial", "fs-1", 2, "OpenedShop")
			a:logFunnelStepEvent(player, "Tutorial", "fs-1", 0, "Bad")
			expect(#queue.events).to.equal(1)
			local e = queue.events[1]
			expect(e.type).to.equal("funnel")
			expect(e.name).to.equal("Tutorial")
			expect(e.data.step).to.equal(2)
			expect(e.data.funnelSessionId).to.equal("fs-1")
			expect(e.data.stepName).to.equal("OpenedShop")
			expect(e.data.onboarding).to.equal(nil)
		end)

		it("onboarding is the Onboarding funnel with flag", function()
			local a = make()
			a:logOnboardingFunnelStepEvent(player, 1, "Spawned")
			local e = queue.events[1]
			expect(e.type).to.equal("funnel")
			expect(e.name).to.equal("Onboarding")
			expect(e.data.onboarding).to.equal(true)
			expect(e.data.step).to.equal(1)
		end)

		it("logProgressionEvent maps status", function()
			local a = make()
			a:logProgressionEvent(player, "Level", Enum.AnalyticsProgressionType.Complete, 5, "Lava")
			local e = queue.events[1]
			expect(e.type).to.equal("progression")
			expect(e.name).to.equal("Level")
			expect(e.data.status).to.equal("complete")
			expect(e.data.level).to.equal(5)
			expect(e.data.levelName).to.equal("Lava")
		end)

		it("drops player events without session", function()
			local a = make()
			sessions.byPlayer[player] = nil
			a:logProgressionEvent(player, "Level", Enum.AnalyticsProgressionType.Start, 1)
			expect(#queue.events).to.equal(0)
		end)

		it("track works without a player", function()
			local a = make()
			a:track("ServerEventStarted", { value = 1, props = { kind = "DoubleXP" } })
			local e = queue.events[1]
			expect(e.type).to.equal("custom")
			expect(e.userId).to.equal(nil)
			expect(e.sessionId).to.equal(nil)
			expect(e.value).to.equal(1)
			expect(e.data.kind).to.equal("DoubleXP")
		end)

		it("drops invalid names", function()
			local a = make()
			a:track("", nil)
			expect(#queue.events).to.equal(0)
		end)
	end)

	describe("forwardToRobloxAnalytics", function()
		it("does not forward when disabled", function()
			local a = make(false)
			a:logCustomEvent(player, "X", 1)
			expect(#native.calls).to.equal(0)
		end)

		it("forwards with original arguments when enabled", function()
			local a = make(true)
			a:logEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Source, "Gems", 5, 10, "Quest")
			a:logOnboardingFunnelStepEvent(player, 1)
			a:track("NoPlayer", nil)
			expect(#native.calls).to.equal(2)
			expect(native.calls[1].method).to.equal("LogEconomyEvent")
			expect(native.calls[1].args[1]).to.equal(player)
			expect(native.calls[1].args[3]).to.equal("Gems")
			expect(native.calls[2].method).to.equal("LogOnboardingFunnelStepEvent")
		end)

		it("survives native errors", function()
			local a = make(true)
			native.LogCustomEvent = function()
				error("native failure")
			end
			a:logCustomEvent(player, "X", 1)
			expect(#queue.events).to.equal(1)
		end)
	end)
end

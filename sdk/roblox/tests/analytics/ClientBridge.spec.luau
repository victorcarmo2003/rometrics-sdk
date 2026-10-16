--!strict
-- TestEZ-style spec for Client/Bridge (player_platform reports).

local RoMetrics = script.Parent.Parent.Parent.RoMetrics
local Bridge = require(RoMetrics.Client.Bridge) :: any
local Fakes = require(script.Parent.Parent.purchases.Fakes)

return function()
	describe("parseReport", function()
		it("accepts known platforms and clamps screen size", function()
			local r = Bridge.parseReport({ platform = "mobile", screenW = 844.6, screenH = 390 })
			expect(r.platform).to.equal("mobile")
			expect(r.screenW).to.equal(844)
			expect(r.screenH).to.equal(390)
		end)
		it("rejects garbage", function()
			expect(Bridge.parseReport(nil)).to.equal(nil)
			expect(Bridge.parseReport("desktop")).to.equal(nil)
			expect(Bridge.parseReport({ platform = "toaster" })).to.equal(nil)
		end)
		it("drops invalid screen values", function()
			local r = Bridge.parseReport({ platform = "desktop", screenW = -1, screenH = 1e9 })
			expect(r.screenW).to.equal(nil)
			expect(r.screenH).to.equal(nil)
		end)
	end)

	describe("start", function()
		local queue: any
		local sessions: any
		local player: any
		local remote: any
		local stop: any

		beforeEach(function()
			queue = Fakes.queue()
			sessions = Fakes.sessions()
			player = Fakes.player(9)
			sessions:add(player)
			remote = Fakes.remoteEvent("RoMetricsClient")
			stop = Bridge.start(Fakes.config(), queue, sessions, {
				replicatedStorage = Fakes.container({ RoMetricsClient = remote }),
				players = Fakes.players({ player }),
				sessionWait = 0,
			})
		end)

		afterEach(function()
			stop()
		end)

		it("emits one player_platform per session", function()
			remote.OnServerEvent:Fire(player, { platform = "tablet", screenW = 1180, screenH = 820 })
			remote.OnServerEvent:Fire(player, { platform = "desktop" })
			expect(#queue.events).to.equal(1)
			local e = queue.events[1]
			expect(e.type).to.equal("player_platform")
			expect(e.userId).to.equal(9)
			expect(e.sessionId).to.equal(sessions:get(player).sessionId)
			expect(e.data.platform).to.equal("tablet")
			expect(e.data.screenW).to.equal(1180)
			expect(sessions:get(player).platform).to.equal("tablet")
		end)

		it("ignores invalid payloads without consuming the slot", function()
			remote.OnServerEvent:Fire(player, { platform = "toaster" })
			remote.OnServerEvent:Fire(player, { platform = "console" })
			expect(#queue.events).to.equal(1)
			expect(queue.events[1].data.platform).to.equal("console")
		end)

		it("drops reports when no session exists", function()
			sessions.byPlayer[player] = nil
			remote.OnServerEvent:Fire(player, { platform = "desktop" })
			expect(#queue.events).to.equal(0)
		end)
	end)
end

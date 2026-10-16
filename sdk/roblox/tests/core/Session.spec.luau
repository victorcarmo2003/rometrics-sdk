--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Session = require(ReplicatedStorage.RoMetrics.Session)

return function()
	describe("parseLaunchCode", function()
		it("reads rm=code", function()
			expect(Session.parseLaunchCode("rm=yt01")).to.equal("yt01")
		end)

		it("reads rm among other params", function()
			expect(Session.parseLaunchCode("foo=1&rm=tiktok_A-2&bar=2")).to.equal("tiktok_A-2")
		end)

		it('reads JSON {"rm":"code"}', function()
			expect(Session.parseLaunchCode('{"rm":"yt01","x":1}')).to.equal("yt01")
		end)

		it("accepts a still-percent-encoded value", function()
			expect(Session.parseLaunchCode("rm%3Dyt01")).to.equal("yt01")
		end)

		it("trims whitespace", function()
			expect(Session.parseLaunchCode("  rm=yt01 ")).to.equal("yt01")
		end)

		it("returns nil when absent or invalid", function()
			expect(Session.parseLaunchCode(nil)).to.equal(nil)
			expect(Session.parseLaunchCode("")).to.equal(nil)
			expect(Session.parseLaunchCode("hello")).to.equal(nil)
			expect(Session.parseLaunchCode("xrm=yt01")).to.equal(nil)
			expect(Session.parseLaunchCode("rm=")).to.equal(nil)
			expect(Session.parseLaunchCode("rm=has space")).to.equal(nil)
			expect(Session.parseLaunchCode("rm=" .. string.rep("a", 65))).to.equal(nil)
			expect(Session.parseLaunchCode('{"rm":5}')).to.equal(nil)
			expect(Session.parseLaunchCode("{not json")).to.equal(nil)
		end)
	end)

	describe("buildJoinSource", function()
		it("handles missing join data", function()
			local source = Session.buildJoinSource(nil)
			expect(source.sourcePlaceId).to.equal(nil)
			expect(source.referredBy).to.equal(nil)
			expect(source.launchCode).to.equal(nil)
			expect(source.teleported).to.equal(false)
		end)

		it("maps join data fields", function()
			local source = Session.buildJoinSource({
				SourcePlaceId = 123,
				ReferredByPlayerId = 456,
				LaunchData = "rm=yt01",
			})
			expect(source.sourcePlaceId).to.equal(123)
			expect(source.referredBy).to.equal(456)
			expect(source.launchCode).to.equal("yt01")
			expect(source.teleported).to.equal(true)
		end)

		it("treats a zero referrer as none", function()
			expect(Session.buildJoinSource({ ReferredByPlayerId = 0 }).referredBy).to.equal(nil)
		end)

		it("falls back to TeleportData.rm", function()
			expect(Session.buildJoinSource({ TeleportData = { rm = "yt01" } }).launchCode).to.equal("yt01")
			expect(Session.buildJoinSource({ LaunchData = "rm=a", TeleportData = { rm = "b" } }).launchCode).to.equal(
				"a"
			)
		end)
	end)
end

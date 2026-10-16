--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.RoMetrics.Config)

return function()
	describe("resolve", function()
		it("applies defaults", function()
			local config = Config.resolve({ key = "rmk_live_x" }, "1.2.3")
			expect(config.endpoint).to.equal("https://ingest.rometrics.app")
			expect(config.flushInterval).to.equal(10)
			expect(config.maxBatchSize).to.equal(100)
			expect(config.maxQueueSize).to.equal(5000)
			expect(config.heartbeatInterval).to.equal(30)
			expect(config.debug).to.equal(false)
			expect(config.enabledInStudio).to.equal(false)
			expect(config.forwardToRobloxAnalytics).to.equal(false)
			expect(config.sdkVersion).to.equal("1.2.3")
		end)

		it("requires a key", function()
			expect(function()
				Config.resolve({}, "1")
			end).to.throw()
			expect(function()
				Config.resolve({ key = "" }, "1")
			end).to.throw()
			expect(function()
				Config.resolve({ key = 5 :: any }, "1")
			end).to.throw()
		end)

		it("strips trailing slashes from the endpoint", function()
			expect(Config.resolve({ key = "k", endpoint = "http://localhost:4100/" }, "1").endpoint).to.equal(
				"http://localhost:4100"
			)
		end)

		it("rejects cleartext http for non-loopback hosts and embedded credentials", function()
			local default = "https://ingest.rometrics.app"
			expect(Config.resolve({ key = "k", endpoint = "http://ingest.example.com" }, "1").endpoint).to.equal(default)
			expect(Config.resolve({ key = "k", endpoint = "http://localhost.evil.com" }, "1").endpoint).to.equal(default)
			expect(Config.resolve({ key = "k", endpoint = "https://u:p@ingest.example.com" }, "1").endpoint).to.equal(default)
			expect(Config.resolve({ key = "k", endpoint = "https://ingest.example.com/" }, "1").endpoint).to.equal(
				"https://ingest.example.com"
			)
		end)

		it("falls back to defaults for invalid values", function()
			local config = Config.resolve({
				key = "k",
				endpoint = "ftp://nope",
				flushInterval = "fast" :: any,
				debug = "yes" :: any,
			}, "1")
			expect(config.endpoint).to.equal("https://ingest.rometrics.app")
			expect(config.flushInterval).to.equal(10)
			expect(config.debug).to.equal(false)
		end)

		it("clamps out-of-range numbers", function()
			local config = Config.resolve({ key = "k", maxBatchSize = 10000, heartbeatInterval = 1 }, "1")
			expect(config.maxBatchSize).to.equal(Config.MAX_EVENTS_PER_BATCH)
			expect(config.heartbeatInterval).to.equal(5)
		end)

		it("keeps maxQueueSize >= maxBatchSize", function()
			local config = Config.resolve({ key = "k", maxBatchSize = 200, maxQueueSize = 50 }, "1")
			expect(config.maxQueueSize).to.equal(200)
		end)
	end)
end

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Transport = require(ReplicatedStorage.RoMetrics.Transport)
local Fakes = require(script.Parent.Fakes)

return function()
	local serverInfo = {
		universeId = 1,
		placeId = 2,
		placeVersion = 3,
		jobId = "job-1",
		private = false,
		startedAt = 1760530000000,
	}

	local function setup(response: { [string]: any }?, throws: boolean?)
		local requests: { { [string]: any } } = {}
		local transport = Transport.new(Fakes.config(), {
			request = function(req: any): any
				table.insert(requests, req)
				if throws then
					error("HttpError: ConnectFail")
				end
				return response or { Success = true, StatusCode = 202, Body = "{}" }
			end,
			serverInfo = function()
				return serverInfo
			end,
			now = function()
				return 1760530012345
			end,
		})
		return transport, requests
	end

	describe("classify", function()
		it("maps status codes", function()
			expect(Transport.classify(202)).to.equal("ok")
			expect(Transport.classify(200)).to.equal("ok")
			expect(Transport.classify(400)).to.equal("drop")
			expect(Transport.classify(413)).to.equal("drop")
			expect(Transport.classify(401)).to.equal("fatal")
			expect(Transport.classify(403)).to.equal("fatal")
			expect(Transport.classify(429)).to.equal("retry")
			expect(Transport.classify(500)).to.equal("retry")
			expect(Transport.classify(503)).to.equal("retry")
			expect(Transport.classify(408)).to.equal("retry")
		end)
	end)

	describe("parseRetryAfter", function()
		it("reads delta-seconds case-insensitively", function()
			expect(Transport.parseRetryAfter({ ["Retry-After"] = "12" })).to.equal(12)
			expect(Transport.parseRetryAfter({ ["retry-after"] = "3" })).to.equal(3)
		end)

		it("ignores missing or non-numeric values", function()
			expect(Transport.parseRetryAfter(nil)).to.equal(nil)
			expect(Transport.parseRetryAfter({})).to.equal(nil)
			expect(Transport.parseRetryAfter({ ["Retry-After"] = "Wed, 21 Oct 2026 07:28:00 GMT" })).to.equal(nil)
		end)
	end)

	describe("send", function()
		it("POSTs the envelope to {endpoint}/v1/batch with the key header", function()
			local transport, requests = setup()
			local event = Fakes.event()
			expect(transport:send({ event })).to.equal("ok")
			expect(#requests).to.equal(1)
			local req = requests[1]
			expect(req.Url).to.equal("http://localhost:4100/v1/batch")
			expect(req.Method).to.equal("POST")
			expect(req.Headers["x-rometrics-key"]).to.equal("rmk_live_test")
			expect(req.Headers["Content-Type"]).to.equal("application/json")

			local body = HttpService:JSONDecode(req.Body)
			expect(body.sdk.name).to.equal("rometrics-luau")
			expect(body.sdk.version).to.equal("0.0.0-test")
			expect(body.server.jobId).to.equal("job-1")
			expect(body.server.universeId).to.equal(1)
			expect(body.sentAt).to.equal(1760530012345)
			expect(#body.events).to.equal(1)
			expect(body.events[1].id).to.equal(event.id)
		end)

		it("strips empty data tables (would encode as [])", function()
			local transport, requests = setup()
			local event = Fakes.event()
			event.data = {}
			transport:send({ event })
			local body = HttpService:JSONDecode(requests[1].Body)
			expect(body.events[1].data).to.equal(nil)
		end)

		it("gzips only large bodies", function()
			local transport, requests = setup()
			transport:send({ Fakes.event() })
			expect(requests[1].Compress).to.equal(Enum.HttpCompression.None)
			local many = {}
			for i = 1, 50 do
				many[i] = Fakes.event()
			end
			transport:send(many)
			expect(requests[2].Compress).to.equal(Enum.HttpCompression.Gzip)
		end)

		it("maps HTTP responses to statuses", function()
			expect((setup({ Success = false, StatusCode = 400, Body = "bad" })):send({ Fakes.event() })).to.equal(
				"drop"
			)
			expect((setup({ Success = false, StatusCode = 401 })):send({ Fakes.event() })).to.equal("fatal")
			expect((setup({ Success = false, StatusCode = 502 })):send({ Fakes.event() })).to.equal("retry")
		end)

		it("exposes retry-after on 429", function()
			local transport = setup({ Success = false, StatusCode = 429, Headers = { ["retry-after"] = "20" } })
			expect(transport:send({ Fakes.event() })).to.equal("retry")
			expect(transport.retryAfter).to.equal(20)
		end)

		it("returns retry when the request throws", function()
			local transport = setup(nil, true)
			expect(transport:send({ Fakes.event() })).to.equal("retry")
			expect(transport.retryAfter).to.equal(nil)
		end)

		it("splits bodies over MAX_BODY_BYTES into smaller requests", function()
			local transport, requests = setup()
			local events = {}
			for i = 1, 4 do
				local event = Fakes.event()
				event.data = { blob = string.rep("x", 300_000) }
				events[i] = event
			end
			expect(transport:send(events)).to.equal("ok")
			expect(#requests > 1).to.equal(true)
			local total = 0
			for _, req in requests do
				expect(#req.Body <= Transport.MAX_BODY_BYTES).to.equal(true)
				total += #HttpService:JSONDecode(req.Body).events
			end
			expect(total).to.equal(4)
		end)

		it("drops a single event that can never fit", function()
			local transport, requests = setup()
			local event = Fakes.event()
			event.data = { blob = string.rep("x", Transport.MAX_BODY_BYTES) }
			expect(transport:send({ event })).to.equal("drop")
			expect(#requests).to.equal(0)
		end)
	end)

	describe("messages", function()
		it("detects the HTTP-disabled error", function()
			expect(Transport.isHttpDisabledError("Http requests are not enabled. Enable via game settings")).to.equal(
				true
			)
			expect(Transport.isHttpDisabledError("HttpError: ConnectFail")).to.equal(false)
		end)

		it("explains universe mismatches", function()
			local msg = Transport.fatalMessage(403, '{"error":"universe_mismatch"}', 0)
			expect(string.find(msg, "Universe ID 0", 1, true) ~= nil).to.equal(true)
			expect(string.find(msg, "publish the place", 1, true) ~= nil).to.equal(true)
			expect(string.find(Transport.fatalMessage(401, nil, 5), "invalid or revoked", 1, true) ~= nil).to.equal(
				true
			)
		end)
	end)
end

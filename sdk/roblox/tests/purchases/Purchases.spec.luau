--!strict
-- TestEZ-style spec for Purchases (ProcessReceipt wrapper + game passes).

local RoMetrics = script.Parent.Parent.Parent.RoMetrics
local Purchases = require(RoMetrics.Purchases) :: any
local Fakes = require(script.Parent.Fakes)

local Granted = Enum.ProductPurchaseDecision.PurchaseGranted
local NotYet = Enum.ProductPurchaseDecision.NotProcessedYet

return function()
	local queue: any
	local sessions: any
	local player: any
	local marketplace: any
	local delayed: { () -> () }

	local function receipt(overrides: { [string]: any }?): { [string]: any }
		local r: { [string]: any } = {
			PlayerId = 42,
			ProductId = 1001,
			PurchaseId = "abc-123",
			CurrencySpent = 49,
			CurrencyType = Enum.CurrencyType.Robux,
			PlaceIdWherePurchased = 1,
		}
		if overrides then
			for k, v in overrides do
				r[k] = v
			end
		end
		return r
	end

	local function setup(started: boolean)
		Purchases._reset()
		queue = Fakes.queue()
		sessions = Fakes.sessions()
		player = Fakes.player(42)
		sessions:add(player)
		marketplace = Fakes.marketplace({
			[1001] = { Name = "100 Coins", PriceInRobux = 50 },
			[2002] = { Name = "VIP", PriceInRobux = 399 },
		})
		delayed = {}
		Purchases._setDeps({
			marketplace = marketplace,
			players = Fakes.players({ player }),
			retryDelay = 0,
			delay = function(_seconds: number, fn: () -> ())
				table.insert(delayed, fn)
			end,
		})
		if started then
			Purchases.start(Fakes.config(), queue, sessions)
		end
	end

	afterEach(function()
		Purchases._reset()
	end)

	describe("wrapProcessReceipt", function()
		it("preserves the handler decision and receives receiptInfo", function()
			setup(true)
			local seen: any = nil
			local wrapped = Purchases.wrapProcessReceipt(function(info)
				seen = info
				return NotYet
			end)
			local r = receipt()
			expect(wrapped(r)).to.equal(NotYet)
			expect(seen).to.equal(r)
			expect(#queue.events).to.equal(0)
		end)

		it("returns NotProcessedYet when the handler errors", function()
			setup(true)
			local wrapped = Purchases.wrapProcessReceipt(function(_info)
				error("boom")
			end)
			expect(wrapped(receipt())).to.equal(NotYet)
			expect(#queue.events).to.equal(0)
		end)

		it("emits a devproduct purchase only on PurchaseGranted", function()
			setup(true)
			local wrapped = Purchases.wrapProcessReceipt(function(_info)
				return Granted
			end)
			expect(wrapped(receipt())).to.equal(Granted)
			expect(#queue.events).to.equal(1)
			local event = queue.events[1]
			expect(event.type).to.equal("purchase")
			expect(event.userId).to.equal(42)
			expect(event.sessionId).to.equal(sessions:get(player).sessionId)
			expect(event.data.kind).to.equal("devproduct")
			expect(event.data.productId).to.equal(1001)
			expect(event.data.receiptId).to.equal("abc-123")
			-- CurrencySpent wins over the catalog price.
			expect(event.data.priceRobux).to.equal(49)
			expect(event.data.name).to.equal("100 Coins")
		end)

		it("tracks each PurchaseId once", function()
			setup(true)
			local wrapped = Purchases.wrapProcessReceipt(function(_info)
				return Granted
			end)
			wrapped(receipt())
			wrapped(receipt())
			expect(#queue.events).to.equal(1)
		end)

		it("works without init (handler runs, nothing tracked)", function()
			setup(false)
			local calls = 0
			local wrapped = Purchases.wrapProcessReceipt(function(_info)
				calls += 1
				return Granted
			end)
			expect(wrapped(receipt())).to.equal(Granted)
			expect(calls).to.equal(1)
			expect(#queue.events).to.equal(0)
		end)

		it("skips players without a session", function()
			setup(true)
			sessions.byPlayer[player] = nil
			local wrapped = Purchases.wrapProcessReceipt(function(_info)
				return Granted
			end)
			expect(wrapped(receipt())).to.equal(Granted)
			expect(#queue.events).to.equal(0)
		end)

		it("still tracks when GetProductInfo keeps failing (no name)", function()
			setup(true)
			marketplace.failuresLeft = 10
			local wrapped = Purchases.wrapProcessReceipt(function(_info)
				return Granted
			end)
			wrapped(receipt())
			expect(#queue.events).to.equal(1)
			expect(queue.events[1].data.name).to.equal(nil)
			expect(queue.events[1].data.priceRobux).to.equal(49)
		end)
	end)

	describe("trackReceipt", function()
		it("records a receipt granted by a ProcessReceipt the game owns", function()
			setup(true)
			Purchases.trackReceipt(receipt())
			Purchases.trackReceipt(receipt())
			expect(#queue.events).to.equal(1)
			expect(queue.events[1].data.kind).to.equal("devproduct")
			expect(queue.events[1].data.receiptId).to.equal("abc-123")
		end)

		it("ignores non-table input", function()
			setup(true)
			Purchases.trackReceipt(nil :: any)
			expect(#queue.events).to.equal(0)
		end)
	end)

	describe("non-decision returns", function()
		it("turns a nil return into NotProcessedYet without tracking", function()
			setup(true)
			local wrapped = Purchases.wrapProcessReceipt(function(_info)
				return nil :: any
			end)
			expect(wrapped(receipt())).to.equal(NotYet)
			expect(#queue.events).to.equal(0)
		end)
	end)

	describe("override diagnostic", function()
		local function warnings(fn: () -> ()): { string }
			local Log = require(RoMetrics.Util.Log) :: any
			local original = Log.warn
			local seen = {}
			Log.warn = function(message: string)
				table.insert(seen, message)
			end
			local ok, err = pcall(fn)
			Log.warn = original
			if not ok then
				error(err)
			end
			return seen
		end

		it("warns once when a bought product never reached a wrapped callback", function()
			setup(true)
			local seen = warnings(function()
				marketplace.PromptProductPurchaseFinished:Fire(42, 1001, true)
				marketplace.PromptProductPurchaseFinished:Fire(42, 1001, true)
				for _, fn in delayed do
					fn()
				end
			end)
			expect(#seen).to.equal(1)
			expect(string.find(seen[1], "ProcessReceipt", 1, true)).to.be.ok()
		end)

		it("stays quiet when the wrapper saw the receipt", function()
			setup(true)
			local wrapped = Purchases.wrapProcessReceipt(function(_info)
				return Granted
			end)
			local seen = warnings(function()
				marketplace.PromptProductPurchaseFinished:Fire(42, 1001, true)
				wrapped(receipt())
				for _, fn in delayed do
					fn()
				end
			end)
			expect(#seen).to.equal(0)
		end)

		it("stays quiet when trackReceipt saw the receipt", function()
			setup(true)
			local seen = warnings(function()
				Purchases.trackReceipt(receipt())
				marketplace.PromptProductPurchaseFinished:Fire(42, 1001, true)
				for _, fn in delayed do
					fn()
				end
			end)
			expect(#seen).to.equal(0)
		end)

		it("ignores cancelled product prompts", function()
			setup(true)
			marketplace.PromptProductPurchaseFinished:Fire(42, 1001, false)
			expect(#delayed).to.equal(0)
		end)

		it("starts when the marketplace has no PromptProductPurchaseFinished", function()
			setup(false)
			marketplace.PromptProductPurchaseFinished = nil
			Purchases.start(Fakes.config(), queue, sessions)
			expect(marketplace.PromptGamePassPurchaseFinished:count()).to.equal(1)
		end)
	end)

	describe("game passes", function()
		it("emits a gamepass purchase with catalog name/price when purchased", function()
			setup(true)
			marketplace.PromptGamePassPurchaseFinished:Fire(player, 2002, true)
			expect(#queue.events).to.equal(1)
			local event = queue.events[1]
			expect(event.type).to.equal("purchase")
			expect(event.data.kind).to.equal("gamepass")
			expect(event.data.productId).to.equal(2002)
			expect(event.data.name).to.equal("VIP")
			expect(event.data.priceRobux).to.equal(399)
			expect(event.data.receiptId).to.equal(nil)
		end)

		it("ignores cancelled prompts", function()
			setup(true)
			marketplace.PromptGamePassPurchaseFinished:Fire(player, 2002, false)
			expect(#queue.events).to.equal(0)
		end)

		it("caches GetProductInfo and retries failures", function()
			setup(true)
			marketplace.failuresLeft = 1
			marketplace.PromptGamePassPurchaseFinished:Fire(player, 2002, true)
			marketplace.PromptGamePassPurchaseFinished:Fire(player, 2002, true)
			expect(#queue.events).to.equal(2)
			-- 1 failure + 1 success, second event served from cache.
			expect(marketplace.calls).to.equal(2)
		end)

		it("connects only once across repeated start calls", function()
			setup(true)
			Purchases.start(Fakes.config(), queue, sessions)
			expect(marketplace.PromptGamePassPurchaseFinished:count()).to.equal(1)
			expect(marketplace.PromptProductPurchaseFinished:count()).to.equal(1)
		end)
	end)
end

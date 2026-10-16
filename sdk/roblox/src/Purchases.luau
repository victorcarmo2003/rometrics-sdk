--!strict
--[[
	Purchase tracking.

	Developer products
		`wrapProcessReceipt(handler)` returns a ProcessReceipt callback that:
		  * runs the game's handler inside `pcall` and returns its decision unchanged;
		  * if the handler throws, logs a warning and returns `NotProcessedYet` so Roblox
		    retries the receipt later (the player is never charged for an ungranted item);
		  * emits a `purchase` event (kind = "devproduct") only when the decision is
		    `PurchaseGranted`: productId = ProductId, receiptId = PurchaseId,
		    priceRobux = CurrencySpent, name from a cached `GetProductInfo` lookup;
		  * never yields extra time in the receipt path: tracking runs in `task.spawn`;
		  * works before/without `init`: the handler still runs, purchases are simply not tracked.
		`MarketplaceService.ProcessReceipt` is a callback with a single owner: the last script that assigns
		it wins. Wrap the one callback your game already assigns (e.g. inside its shop service) instead of
		assigning a second one, or call `trackReceipt(receiptInfo)` from that callback once it grants.

	Override diagnostic
		After `start`, a granted developer product prompt (`PromptProductPurchaseFinished`) that no wrapped
		callback / `trackReceipt` saw within RECEIPT_GRACE_S logs one warning: another script owns
		ProcessReceipt and purchases are not being tracked.

	Game passes
		Tracked automatically after `start` via `MarketplaceService.PromptGamePassPurchaseFinished`
		(server side) when `wasPurchased` is true. Name/price come from
		`GetProductInfo(id, Enum.InfoType.GamePass)` (cached, pcall + retries). Game passes bought
		outside the experience (website) are not observable and therefore not tracked.

	Subscriptions
		Not tracked yet (kind "subscription" is reserved in the wire contract).

	Purchases need a live session (userId + sessionId are mandatory on the wire); receipts for
	players without a session (left, or init not called) are skipped with a debug log.
]]

local Types = require(script.Parent.Types)
local Log = require(script.Parent.Util.Log)
local Uuid = require(script.Parent.Util.Uuid)
local Clock = require(script.Parent.Util.Clock)

type ProductInfo = { name: string?, price: number? }

-- Minimal surface used from MarketplaceService / Players; injectable for tests.
export type Deps = {
	marketplace: any,
	players: any,
	-- Seconds between GetProductInfo retries (0 in tests).
	retryDelay: number?,
	-- task.delay replacement (tests run the override check by hand).
	delay: ((seconds: number, fn: () -> ()) -> ())?,
}

local PRODUCT_INFO_TTL_S = 600
local PRODUCT_INFO_ATTEMPTS = 3
local MAX_SEEN_RECEIPTS = 1000
-- ProcessReceipt can run some seconds after the prompt closes (and games may yield on saves).
local RECEIPT_GRACE_S = 30
local MAX_RECEIPT_CALLS = 1000

local Purchases = {}

type CacheEntry = { info: ProductInfo, expires: number }

type State = {
	queue: Types.Queue?,
	sessions: Types.SessionTracker?,
	deps: Deps?,
	cache: { [string]: CacheEntry },
	seenReceipts: { [string]: boolean },
	seenOrder: { string },
	connection: RBXScriptConnection?,
	productConnection: RBXScriptConnection?,
	-- "playerId:productId" -> os.clock() of the last receipt a wrapper / trackReceipt saw.
	receiptCalls: { [string]: number },
	receiptCallCount: number,
	overrideWarned: boolean,
}

local state: State = {
	queue = nil,
	sessions = nil,
	deps = nil,
	cache = {},
	seenReceipts = {},
	seenOrder = {},
	connection = nil,
	productConnection = nil,
	receiptCalls = {},
	receiptCallCount = 0,
	overrideWarned = false,
}

local function getDeps(): Deps
	local deps = state.deps
	if deps then
		return deps
	end
	local defaults: Deps = {
		marketplace = game:GetService("MarketplaceService"),
		players = game:GetService("Players"),
		retryDelay = 1,
	}
	state.deps = defaults
	return defaults
end

local function toPrice(value: unknown): number
	if type(value) == "number" and value == value and value >= 0 and value < math.huge then
		return math.floor(value)
	end
	return 0
end

local function truncate(value: unknown, max: number): string?
	if type(value) ~= "string" or value == "" then
		return nil
	end
	return string.sub(value, 1, max)
end

-- Cached, retried GetProductInfo. Returns empty info on failure (never throws).
local function getProductInfo(productId: number, infoType: Enum.InfoType): ProductInfo
	local key = `{infoType.Name}:{productId}`
	local now = os.clock()
	local cached = state.cache[key]
	if cached and cached.expires > now then
		return cached.info
	end
	local deps = getDeps()
	for attempt = 1, PRODUCT_INFO_ATTEMPTS do
		local ok, result = pcall(function()
			return deps.marketplace:GetProductInfo(productId, infoType)
		end)
		if ok and type(result) == "table" then
			local raw = result :: { [string]: unknown }
			local info: ProductInfo = {
				name = truncate(raw.Name, 200),
				price = if type(raw.PriceInRobux) == "number" then raw.PriceInRobux :: number else nil,
			}
			state.cache[key] = { info = info, expires = now + PRODUCT_INFO_TTL_S }
			return info
		end
		Log.debug(`GetProductInfo({key}) attempt {attempt} failed: {result}`)
		if attempt < PRODUCT_INFO_ATTEMPTS then
			local delay = deps.retryDelay or 1
			if delay > 0 then
				task.wait(delay * attempt)
			end
		end
	end
	return {}
end

-- Returns true the first time a receipt id is seen (bounded memory).
local function markReceipt(receiptId: string): boolean
	if state.seenReceipts[receiptId] then
		return false
	end
	state.seenReceipts[receiptId] = true
	table.insert(state.seenOrder, receiptId)
	if #state.seenOrder > MAX_SEEN_RECEIPTS then
		local oldest = table.remove(state.seenOrder, 1)
		if oldest then
			state.seenReceipts[oldest] = nil
		end
	end
	return true
end

local function emit(
	player: Player,
	kind: "devproduct" | "gamepass",
	productId: number,
	name: string?,
	priceRobux: number,
	receiptId: string?
)
	local queue = state.queue
	local sessions = state.sessions
	if not queue or not sessions then
		return
	end
	local session = sessions:get(player)
	if not session then
		Log.debug(`purchase {kind}:{productId} skipped: no session for {player.UserId}`)
		return
	end
	local data: { [string]: any } = {
		kind = kind,
		productId = productId,
		priceRobux = priceRobux,
	}
	if name then
		data.name = name
	end
	if receiptId then
		data.receiptId = receiptId
	end
	queue:push({
		id = Uuid(),
		type = "purchase",
		ts = Clock(),
		userId = session.userId,
		sessionId = session.sessionId,
		data = data,
	})
end

local function trackReceipt(receiptInfo: { [string]: any })
	if not state.queue then
		return
	end
	local productId = receiptInfo.ProductId
	local playerId = receiptInfo.PlayerId
	if type(productId) ~= "number" or type(playerId) ~= "number" then
		Log.debug("purchase skipped: malformed receiptInfo")
		return
	end
	local receiptId = truncate(if receiptInfo.PurchaseId ~= nil then tostring(receiptInfo.PurchaseId) else nil, 100)
	if receiptId and state.seenReceipts[receiptId] then
		Log.debug(`purchase receipt {receiptId} already tracked`)
		return
	end
	local deps = getDeps()
	local player = deps.players:GetPlayerByUserId(playerId)
	if not player then
		Log.debug(`purchase skipped: player {playerId} not in server`)
		return
	end
	local info = getProductInfo(productId, Enum.InfoType.Product)
	-- CurrencySpent is what the player actually paid (sales/discounts included).
	local price = if receiptInfo.CurrencySpent ~= nil then toPrice(receiptInfo.CurrencySpent) else toPrice(info.price)
	-- Mark only after the (yielding) lookup, right before emitting, so concurrent duplicates dedupe
	-- and a failure above does not swallow a later retry of the same receipt.
	if receiptId and not markReceipt(receiptId) then
		Log.debug(`purchase receipt {receiptId} already tracked`)
		return
	end
	emit(player, "devproduct", productId, info.name, price, receiptId)
end

local function onGamePassFinished(player: Player, gamePassId: number, wasPurchased: boolean)
	if not wasPurchased or type(gamePassId) ~= "number" then
		return
	end
	local info = getProductInfo(gamePassId, Enum.InfoType.GamePass)
	emit(player, "gamepass", gamePassId, info.name, toPrice(info.price), nil)
end

local function receiptKey(playerId: unknown, productId: unknown): string
	return `{playerId}:{productId}`
end

-- Remembers that the SDK saw a receipt (feeds the override diagnostic). Never yields.
local function noteReceipt(receiptInfo: { [string]: any })
	if state.receiptCallCount >= MAX_RECEIPT_CALLS then
		state.receiptCalls = {}
		state.receiptCallCount = 0
	end
	local key = receiptKey(receiptInfo.PlayerId, receiptInfo.ProductId)
	if state.receiptCalls[key] == nil then
		state.receiptCallCount += 1
	end
	state.receiptCalls[key] = os.clock()
end

local function onProductFinished(userId: unknown, productId: unknown, isPurchased: unknown)
	if isPurchased ~= true or state.overrideWarned then
		return
	end
	local key = receiptKey(userId, productId)
	local finishedAt = os.clock()
	local deps = getDeps()
	local delay = deps.delay or function(seconds: number, fn: () -> ())
		task.delay(seconds, fn)
	end
	delay(RECEIPT_GRACE_S, function()
		local seen = state.receiptCalls[key]
		if state.overrideWarned or (seen ~= nil and seen >= finishedAt - RECEIPT_GRACE_S) then
			return
		end
		state.overrideWarned = true
		Log.warn(
			`developer product {productId} was bought but no RoMetrics.wrapProcessReceipt callback saw the receipt: `
				.. "another script assigns MarketplaceService.ProcessReceipt (only the last assignment wins). "
				.. "Wrap that callback with RoMetrics.wrapProcessReceipt, or call RoMetrics.trackReceipt(receiptInfo) "
				.. "where it grants. Purchases are not being tracked."
		)
	end)
end

function Purchases.start(_config: Types.Config, queue: Types.Queue, sessions: Types.SessionTracker)
	state.queue = queue
	state.sessions = sessions
	if state.connection then
		state.connection:Disconnect()
	end
	if state.productConnection then
		state.productConnection:Disconnect()
		state.productConnection = nil
	end
	local deps = getDeps()
	state.connection = deps.marketplace.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, gamePassId: number, wasPurchased: boolean)
			local ok, err = pcall(function()
					onGamePassFinished(player, gamePassId, wasPurchased)
				end)
			if not ok then
				Log.warn(`game pass tracking failed: {err}`)
			end
		end
	)
	-- Diagnostic only (deprecated event, still fired on the server): optional so a missing event never breaks start.
	local hooked, productSignal = pcall(function()
		return deps.marketplace.PromptProductPurchaseFinished
	end)
	if hooked and productSignal ~= nil then
		state.productConnection = productSignal:Connect(function(userId: number, productId: number, isPurchased: boolean)
			local ok, err = pcall(onProductFinished, userId, productId, isPurchased)
			if not ok then
				Log.debug(`receipt override check failed: {err}`)
			end
		end)
	end
end

-- Records a granted developer product receipt. For games whose ProcessReceipt lives in their own framework:
-- call it from that callback right before returning PurchaseGranted. Never yields, never throws; duplicates
-- (same PurchaseId) are tracked once.
function Purchases.trackReceipt(receiptInfo: { [string]: any })
	if type(receiptInfo) ~= "table" then
		return
	end
	noteReceipt(receiptInfo)
	task.spawn(function()
		local tracked, err = pcall(function()
			trackReceipt(receiptInfo)
		end)
		if not tracked then
			Log.warn(`purchase tracking failed: {err}`)
		end
	end)
end

function Purchases.wrapProcessReceipt(
	handler: (receiptInfo: { [string]: any }) -> Enum.ProductPurchaseDecision
): (receiptInfo: { [string]: any }) -> Enum.ProductPurchaseDecision
	return function(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
		if type(receiptInfo) == "table" then
			noteReceipt(receiptInfo)
		end
		local ok, decision = pcall(handler, receiptInfo)
		if not ok then
			Log.warn(`ProcessReceipt handler errored (returning NotProcessedYet): {decision}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if decision == Enum.ProductPurchaseDecision.PurchaseGranted then
			Purchases.trackReceipt(receiptInfo)
		elseif decision ~= Enum.ProductPurchaseDecision.NotProcessedYet then
			-- nil / anything else: Roblox treats it as not processed; say so instead of failing silently.
			Log.warn(`ProcessReceipt handler returned {decision} (expected an Enum.ProductPurchaseDecision): NotProcessedYet`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return decision
	end
end

-- Test hooks. Not part of the public API.
function Purchases._setDeps(deps: Deps?)
	state.deps = deps
end

function Purchases._reset()
	if state.connection then
		state.connection:Disconnect()
	end
	if state.productConnection then
		state.productConnection:Disconnect()
	end
	state.queue = nil
	state.sessions = nil
	state.deps = nil
	state.cache = {}
	state.seenReceipts = {}
	state.seenOrder = {}
	state.connection = nil
	state.productConnection = nil
	state.receiptCalls = {}
	state.receiptCallCount = 0
	state.overrideWarned = false
end

return Purchases

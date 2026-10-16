--!strict
--[[
	Example server Script (ServerScriptService) showing a full RoMetrics setup.
	Works with the model (ReplicatedStorage.RoMetrics) or Wally (ReplicatedStorage.Packages.RoMetrics).
]]

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local packages = ReplicatedStorage:FindFirstChild("Packages")
local RoMetrics = require(
	(if packages then packages:FindFirstChild("RoMetrics") else nil) or ReplicatedStorage:WaitForChild("RoMetrics")
) :: any

-- 1. Init (server only). In live servers the key comes from the Secrets Store
-- (Creator Hub > experience > Secrets). Local Studio playtests can't read it (unless you add a
-- Local Secret in File > Experience Settings > Security), so Studio falls back to a plain string.
local STUDIO_KEY = "rmk_live_YOUR_TEST_KEY" -- Studio-only test key; production reads the Secret
local STUDIO_ENDPOINT = "http://localhost:4100" -- local ingest; use your https endpoint otherwise

local okSecret, secret = pcall(function()
	return HttpService:GetSecret("rometrics_key")
end)
local isStudio = RunService:IsStudio()
RoMetrics.init({
	key = if okSecret then secret elseif isStudio then STUDIO_KEY else nil,
	endpoint = if isStudio then STUDIO_ENDPOINT else nil,
	enabledInStudio = true, -- send while testing in Studio
	forwardToRobloxAnalytics = true, -- also feed Roblox's native Analytics dashboard
	debug = isStudio, -- verbose Output in Studio
})

-- 2. Developer products: wrap your ProcessReceipt. The decision you return is preserved;
-- if your handler errors, RoMetrics returns NotProcessedYet so Roblox retries later.
local COINS_PRODUCT_ID = 1234567
local coins: { [number]: number } = {}

MarketplaceService.ProcessReceipt = RoMetrics.wrapProcessReceipt(function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if receiptInfo.ProductId == COINS_PRODUCT_ID then
		coins[player.UserId] = (coins[player.UserId] or 0) + 100
		RoMetrics:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType.Source,
			"Coins",
			100,
			coins[player.UserId],
			Enum.AnalyticsEconomyTransactionType.IAP.Name,
			"CoinPack100"
		)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end)

-- 3. Game passes are tracked automatically (PromptGamePassPurchaseFinished).

-- 4. Onboarding, funnels, progression and custom events (same signatures as AnalyticsService).
Players.PlayerAdded:Connect(function(player)
	coins[player.UserId] = 0
	RoMetrics:LogOnboardingFunnelStepEvent(player, 1, "Joined")

	player.CharacterAdded:Once(function()
		RoMetrics:LogOnboardingFunnelStepEvent(player, 2, "Spawned")
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	coins[player.UserId] = nil
end)

-- Call these from your own game systems.
local GameHooks = {}

function GameHooks.onShopOpened(player: Player, funnelSessionId: string)
	RoMetrics:LogFunnelStepEvent(player, "Shop", funnelSessionId, 1, "Opened")
end

function GameHooks.onLevelFinished(player: Player, level: number, won: boolean)
	RoMetrics:LogProgressionEvent(
		player,
		"MainPath",
		if won then Enum.AnalyticsProgressionType.Complete else Enum.AnalyticsProgressionType.Fail,
		level,
		`Level{level}`
	)
end

function GameHooks.onBossKilled(player: Player, bossName: string)
	RoMetrics:LogCustomEvent(player, "BossKilled", 1, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = bossName,
	})
end

-- 5. Server-wide events without a player.
RoMetrics:track("ServerEventStarted", { value = 1, props = { kind = "DoubleXP" } })

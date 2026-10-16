# RoMetrics SDK for Roblox — reference for AI assistants

> You are helping a Roblox developer integrate the RoMetrics SDK (real-time analytics: players, sales, custom events). This file is the complete, authoritative API. Do not invent functions, options or events that are not listed here. Answer the user in their own language (often Portuguese). Version: 0.1.0. Human docs: https://victorcarmo2003.github.io/rometrics-sdk/ · Source: https://github.com/victorcarmo2003/rometrics-sdk

## 1. Mental model

- One ModuleScript named `RoMetrics` (usually in `ReplicatedStorage`). **Server-only**: require and call it from Scripts in `ServerScriptService`, never from LocalScripts.
- Call `RoMetrics.init({...})` once at server start. After that, a lot is tracked automatically (servers/CCU, player join/leave, country, Premium, join source, Game Pass purchases, player platform, tagged instances).
- The event API mirrors Roblox `AnalyticsService` exactly (same method names and argument order), called with `:`.
- **No call ever throws** into game code. Invalid input is dropped with a `warn` in Output. Do not wrap SDK calls in `pcall`; it is unnecessary.
- Events are queued and sent in batches over HTTPS from the server to the RoMetrics ingest. Nothing is sent from clients.

## 2. Setup (canonical script)

```lua
--!strict
-- ServerScriptService/RoMetricsSetup (Script)
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RoMetrics = require(ReplicatedStorage:WaitForChild("RoMetrics")) :: any

-- Production: key comes from the Secrets Store. Studio Play cannot read it,
-- so a TEST key string is allowed only when RunService:IsStudio().
local STUDIO_TEST_KEY = "rmk_live_YOUR_TEST_KEY"
local okSecret, secret = pcall(function()
	return HttpService:GetSecret("rometrics_key")
end)
local isStudio = RunService:IsStudio()

RoMetrics.init({
	key = if okSecret then secret elseif isStudio then STUDIO_TEST_KEY else nil,
	enabledInStudio = true, -- default false: nothing is sent during Studio Play
	debug = isStudio,
})

-- Developer products: wrap the game's ProcessReceipt so sales are counted.
MarketplaceService.ProcessReceipt = RoMetrics.wrapProcessReceipt(function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- grant the item and persist it here
	return Enum.ProductPurchaseDecision.PurchaseGranted
end)
```

Prerequisites the user must do outside code:
1. Publish the place (Universe ID 0 is rejected with 403).
2. Turn on **Allow HTTP Requests** (File → Experience Settings → Security).
3. Create an ingest key `rmk_live_...` for this game in the RoMetrics dashboard (Settings → Ingest keys). A key only works for the Universe ID it was created for.
4. Creator Hub → Experience → Secrets → create `rometrics_key` = the key, domain = the ingest host (e.g. `ingest.rometrics.app` or their self-hosted host). For Studio, either a Local Secret (File → Experience Settings → Security → Local Secrets) or the test-key pattern above.

Never put a production key in source code. Never suggest reading the key on the client.

## 3. API

| Member | Kind | Signature |
|---|---|---|
| `RoMetrics.init` | function (`.`) | `init(options: Options): ()` |
| `RoMetrics.wrapProcessReceipt` | function (`.`) | `wrapProcessReceipt(handler: (receiptInfo) -> Enum.ProductPurchaseDecision): (receiptInfo) -> Enum.ProductPurchaseDecision` |
| `RoMetrics:LogCustomEvent` | method (`:`) | `(player: Player, eventName: string, value: number?, customFields: {[string]: any}?)` |
| `RoMetrics:LogEconomyEvent` | method | `(player: Player, flowType: Enum.AnalyticsEconomyFlowType, currencyType: string, amount: number, endingBalance: number, transactionType: string, itemSku: string?, customFields: {[string]: any}?)` |
| `RoMetrics:LogFunnelStepEvent` | method | `(player: Player, funnelName: string, funnelSessionId: string?, step: number, stepName: string?, customFields: {[string]: any}?)` |
| `RoMetrics:LogOnboardingFunnelStepEvent` | method | `(player: Player, step: number, stepName: string?, customFields: {[string]: any}?)` — funnel named `"Onboarding"` |
| `RoMetrics:LogProgressionEvent` | method | `(player: Player, progressionPathName: string, status: Enum.AnalyticsProgressionType, level: number, levelName: string?, customFields: {[string]: any}?)` |
| `RoMetrics:track` | method | `(eventName: string, opts: { player: Player?, value: number?, props: {[string]: any}? }?)` — custom event with or without a player |
| `RoMetrics:flush` | method | `()` — schedule an immediate async send (rarely needed) |
| `RoMetrics.VERSION` | string | `"0.1.0"` |

There are no other public members. In particular there is no `RoMetrics.Track`, `RoMetrics:Log`, `RoMetrics:identify`, `RoMetrics:setUserProperty`, `RoMetrics:shutdown`, or client-side API.

### init options

| Option | Type | Default | Allowed | Notes |
|---|---|---|---|---|
| `key` | `Secret \| string` | required | non-empty | missing/empty → init fails with a warning, SDK stays off, game keeps running |
| `endpoint` | `string` | `"https://ingest.rometrics.app"` | `http(s)://…` | ingest base URL; trailing slashes stripped |
| `flushInterval` | `number` (s) | `10` | 1–300 | |
| `maxBatchSize` | `number` | `100` | 1–500 | |
| `maxQueueSize` | `number` | `5000` | 1–100000, ≥ maxBatchSize | oldest events dropped beyond this |
| `heartbeatInterval` | `number` (s) | `30` | 5–60 | drives live CCU |
| `forwardToRobloxAnalytics` | `boolean` | `false` | | also calls native `AnalyticsService` with the original args |
| `debug` | `boolean` | `false` | | verbose Output (`sent N events (202)`) |
| `enabledInStudio` | `boolean` | `false` | | must be `true` to send during Studio Play |

Invalid optional values fall back to the default (or are clamped) with a warning.

### Semantics

- `flowType`: `Enum.AnalyticsEconomyFlowType.Source` (gained) or `.Sink` (spent); the strings `"Source"`/`"Sink"` (any case) also work.
- `status`: `Enum.AnalyticsProgressionType.Start`, `.Fail`, `.Complete` (or strings). `Custom` is not supported and is dropped.
- `step`: integer starting at 1. `funnelSessionId` (optional, ≤64 chars) groups one attempt through a funnel, e.g. `HttpService:GenerateGUID(false)`.
- `track` without `player` is a server-level event. `track` is not forwarded to native `AnalyticsService`.
- Player events require the player to be in the server and `init` to have run; otherwise they are dropped (debug log `no session`). Calls before `init` are ignored, except `wrapProcessReceipt`, which still runs the handler (just without tracking).
- With `forwardToRobloxAnalytics = true`, native `AnalyticsService` only keeps `customFields` keys from `Enum.AnalyticsCustomFieldKeys.CustomField01..03`.

## 4. Validation rules (apply them when writing code)

- Names (event, funnel, progression path, currency): must match `^[A-Za-z0-9_.:-]{1,64}$`. Other characters become `_`, longer names are cut to 64, empty names are dropped. Prefer `PascalCase` or `snake_case` without spaces: `BossKilled`, `shop_opened`.
- `customFields` / `props`: values must be string, number or boolean (others are `tostring`ed). Keys ≤ 64 chars, string values ≤ 256 chars, total ≈ 2 KB per event; excess keys are dropped in alphabetical order and `_truncated = true` is added. Do not send tables, Instances or Vector3 expecting structure.
- `value`, `amount`, `endingBalance`, `level`: finite numbers.
- `transactionType`, `itemSku`, `stepName`, `levelName`: ≤ 64 chars.

## 5. Purchases

- **Developer Products**: only via `RoMetrics.wrapProcessReceipt(handler)` (note `.`, not `:`). There can be only one `ProcessReceipt` per game: if the game routes products through a table/router, wrap the router function. The wrapper returns exactly the handler's decision; if the handler errors it returns `NotProcessedYet`. A sale is counted only on `PurchaseGranted`, once per `PurchaseId` per server, price = `CurrencySpent`. Do **not** also log the purchase manually with `LogCustomEvent` (it would double count).
- **Game Passes**: automatic (`PromptGamePassPurchaseFinished` with `wasPurchased = true`). Do not add code for them. Purchases made on the website (outside the game) are not observable.
- **Subscriptions**: not tracked in 0.1.0.

## 6. Automatic tracking (no code needed after init)

`server_start`, `heartbeat` (players, maxPlayers, server fps, uptime), `server_stop` (with final flush in `BindToClose`, up to 25 s), `player_join` (country via LocalizationService, Premium, account age, join source: SourcePlaceId, ReferredByPlayerId, LaunchData `rm` code, teleported), `player_leave` (session duration), `player_platform` (desktop/mobile/tablet/console/vr/unknown + screen size, via a LocalScript the SDK installs in StarterPlayerScripts), Game Pass purchases, tagged-instance events.

Studio *Test → Start* players have negative UserIds; the SDK maps them to `10000000000000 + |UserId|`.

## 7. No-code events with tags

Instances tagged `RoMetrics` (CollectionService) with attributes send a custom event when a player interacts:

| Attribute | Type | Required | Meaning |
|---|---|---|---|
| `RM_Event` | string | yes | event name (name rules apply) |
| `RM_Trigger` | string | no | `Touched` \| `ProximityPrompt` \| `ClickDetector` \| `Activated`; inferred from class when absent (ProximityPrompt, ClickDetector, Tool→Activated, BasePart/Model/Folder→Touched) |
| `RM_Value` | number | no | event value |
| `RM_Cooldown` | number (s) | no | per player per instance; `Touched` always has ≥ 1 s |
| `RM_Once` | boolean | no | once per player session per instance |
| `RM_Prop_<key>` | string/number/boolean | no | extra props |

```lua
local CollectionService = game:GetService("CollectionService")
local chest = workspace.Map.Chest
chest:SetAttribute("RM_Event", "ChestOpened")
chest:SetAttribute("RM_Trigger", "ProximityPrompt")
chest:SetAttribute("RM_Once", true)
CollectionService:AddTag(chest, "RoMetrics")
```

Props `trigger` and `instance` (instance name) are added automatically. Changes at runtime are picked up. `GuiButton` is not supported by tags (client-side): use a RemoteEvent and call `LogCustomEvent` on the server, validating input and rate-limiting.

Optional event registry: ModuleScript `ReplicatedStorage.RoMetricsEvents` returning `{ version = 1, events = { { name, description?, kind = "custom"|"funnel"|"progression"|"economy", trigger = "code"|"tag", props? = { {key, type} }, steps? = { {name, event?} } } } }`. Managed by the RoMetrics Studio plugin; the SDK only reads it for debug warnings (unregistered events are still sent).

## 8. Attribution (tracking links)

Dashboard tracking links open the game with `launchData` `rm=<code>` (`https://www.roblox.com/games/start?placeId=<id>&launchData=rm%3D<code>`). The SDK reads it automatically from `player:GetJoinData().LaunchData` (also accepts `a=1&rm=code` and JSON `{"rm":"code"}`; code = letters, digits, `_`, `-`, ≤ 64). For teleports between places, pass `TeleportData = { rm = code }`; the SDK uses it when there is no LaunchData. No other code is needed.

## 9. Reliability facts (do not reimplement these)

Batches every `flushInterval` s or when full; gzip ≥ 1 KB; ≤ 1 MB per request; uses ≤ ~30 HTTP requests/min per server (Roblox limit is 500); retries 429/5xx/network with exponential backoff 2–60 s honoring `Retry-After`; circuit breaker pauses 60 s after 5 failures; 401/403 (bad/revoked/wrong-game key) stops sending until server restart; final flush on `BindToClose`. Do not write your own HTTP calls, retry loops, `BindToClose` flushes or queues for RoMetrics.

## 10. Common mistakes to avoid

- ❌ `require` or call RoMetrics from a LocalScript. ✅ Server Scripts only; use RemoteEvents for client actions.
- ❌ `RoMetrics.LogCustomEvent(player, ...)` (dot). ✅ `RoMetrics:LogCustomEvent(player, ...)` (colon). ❌ `RoMetrics:wrapProcessReceipt(...)`. ✅ `RoMetrics.wrapProcessReceipt(...)`.
- ❌ Calling `init` more than once or from several scripts. ✅ One setup Script; other scripts just `require` and log.
- ❌ Hardcoding the production key. ✅ `HttpService:GetSecret("rometrics_key")`.
- ❌ Expecting data from Studio Play with defaults. ✅ `enabledInStudio = true` while testing.
- ❌ Spaces/accents in names (`"Boss Killed"`, `"Missão"`). ✅ `"BossKilled"`, `"Missao"`.
- ❌ Nested tables in customFields. ✅ Flat primitives.
- ❌ Logging every frame/Touched without cooldown. ✅ Log meaningful actions; tags already debounce.
- ❌ Logging purchases manually or tracking Game Passes by hand. ✅ `wrapProcessReceipt` + automatic Game Pass tracking.
- ❌ Assigning `MarketplaceService.ProcessReceipt` in two places. ✅ One assignment, wrapped.

## 11. Troubleshooting (Output message → fix)

| Message | Fix |
|---|---|
| `HTTP requests are disabled` | enable Allow HTTP Requests |
| `option 'key' is required` / `init failed` | provide the key (Secret, Local Secret, or Studio test key) |
| `Can't find secret with given key` | create the Secret in this environment |
| `disabled in Studio` | `enabledInStudio = true` |
| `server refused the key (401)` | key wrong/revoked: create a new one |
| `server refused the key (403): this key belongs to another game` | create the key for this Universe ID |
| `Universe ID 0 … publish the place first` | publish the place |
| `server returned 429; will retry` | normal, automatic |
| `request failed: ConnectFail` | wrong `endpoint` or ingest down |

## 12. Recipes

```lua
-- Economy: coins earned from a quest and spent in the shop
RoMetrics:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Source, "Coins", 50, coins, "Quest", "DailyQuest")
RoMetrics:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Sink, "Coins", 300, coins, "Shop", "Sword")

-- Funnel: shop flow with one id per attempt
local attempt = HttpService:GenerateGUID(false)
RoMetrics:LogFunnelStepEvent(player, "Shop", attempt, 1, "Opened")
RoMetrics:LogFunnelStepEvent(player, "Shop", attempt, 2, "SelectedItem")
RoMetrics:LogFunnelStepEvent(player, "Shop", attempt, 3, "Bought")

-- Progression
RoMetrics:LogProgressionEvent(player, "World1", Enum.AnalyticsProgressionType.Start, 3, "Lava Cave")
RoMetrics:LogProgressionEvent(player, "World1", Enum.AnalyticsProgressionType.Complete, 3, "Lava Cave")

-- Client UI action → server log (validate + rate limit on the server)
local ShopOpened = ReplicatedStorage:WaitForChild("ShopOpened") :: RemoteEvent
local last: { [Player]: number } = {}
ShopOpened.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if last[player] and now - last[player] < 2 then return end
	last[player] = now
	RoMetrics:LogCustomEvent(player, "ShopOpened")
end)
game:GetService("Players").PlayerRemoving:Connect(function(p) last[p] = nil end)

-- Server-level event
RoMetrics:track("RoundStarted", { value = 1, props = { map = "Desert" } })
```

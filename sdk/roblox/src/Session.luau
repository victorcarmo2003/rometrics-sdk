--!strict
-- player_join / player_leave, join data, country, LaunchData `rm` code.
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LocalizationService = game:GetService("LocalizationService")

local Types = require(script.Parent.Types)
local Uuid = require(script.Parent.Util.Uuid)
local Clock = require(script.Parent.Util.Clock)
local Log = require(script.Parent.Util.Log)
local UserId = require(script.Parent.Util.UserId)

export type JoinSource = {
	sourcePlaceId: number?,
	referredBy: number?,
	launchCode: string?,
	teleported: boolean,
}

local Session = {}

-- Sessions stay readable this long after PlayerRemoving so other PlayerRemoving handlers
-- (purchases, client bridge) can still attribute events to them.
Session.RETAIN_AFTER_LEAVE_S = 5

local MAX_LAUNCH_DATA = 2048

local function validCode(value: unknown): string?
	if typeof(value) ~= "string" then
		return nil
	end
	local code = value :: string
	if #code >= 1 and #code <= 64 and string.match(code, "^[%w_%-]+$") then
		return code
	end
	return nil
end

local function urlDecode(s: string): string
	local plus = string.gsub(s, "+", " ")
	return (string.gsub(plus, "%%(%x%x)", function(hex: string)
		return string.char(tonumber(hex, 16) :: number)
	end))
end

local function parseOnce(data: string): string?
	if string.sub(data, 1, 1) == "{" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, data)
		if ok and typeof(decoded) == "table" then
			return validCode((decoded :: { [string]: unknown }).rm)
		end
		return nil
	end
	for pair in string.gmatch(data, "[^&]+") do
		local key, value = string.match(pair, "^([^=]*)=(.*)$")
		if key and value and urlDecode(key) == "rm" then
			return validCode(urlDecode(value))
		end
	end
	return nil
end

-- Parses LaunchData ("rm=code", "...&rm=code", or JSON {"rm":"code"}). Pure; unit tested.
-- Also accepts a still-percent-encoded value ("rm%3Dcode"). Returns nil when absent/invalid.
function Session.parseLaunchCode(launchData: string?): string?
	if typeof(launchData) ~= "string" then
		return nil
	end
	local data = string.match(launchData :: string, "^%s*(.-)%s*$") :: string
	if data == "" or #data > MAX_LAUNCH_DATA then
		return nil
	end
	local code = parseOnce(data)
	if code == nil and string.find(data, "%", 1, true) then
		code = parseOnce(urlDecode(data))
	end
	return code
end

local function positiveId(value: unknown): number?
	if typeof(value) == "number" and value > 0 and value == math.floor(value) then
		return value :: number
	end
	return nil
end

-- Builds the joinSource payload from player:GetJoinData(). Pure; unit tested.
-- LaunchData wins; a TeleportData.rm string (set by the game when teleporting) is the fallback.
function Session.buildJoinSource(joinData: { [string]: any }?): JoinSource
	local jd: { [string]: any } = joinData or {}
	local sourcePlaceId = positiveId(jd.SourcePlaceId)
	local launchCode =
		Session.parseLaunchCode(if typeof(jd.LaunchData) == "string" then jd.LaunchData :: string else nil)
	local teleportData = jd.TeleportData
	if launchCode == nil and typeof(teleportData) == "table" then
		launchCode = validCode((teleportData :: { [string]: unknown }).rm)
	end
	return {
		sourcePlaceId = sourcePlaceId,
		referredBy = positiveId(jd.ReferredByPlayerId),
		launchCode = launchCode,
		teleported = sourcePlaceId ~= nil,
	}
end

local function country(player: Player): string?
	local ok, result = pcall(LocalizationService.GetCountryRegionForPlayerAsync, LocalizationService, player)
	if ok and typeof(result) == "string" and string.match(result, "^%a%a$") then
		return string.upper(result)
	end
	return nil
end

local function joinData(player: Player): { [string]: unknown }?
	local ok, result = pcall(player.GetJoinData, player)
	if ok and typeof(result) == "table" then
		return (result :: any) :: { [string]: unknown }
	end
	return nil
end

function Session.start(_config: Types.Config, queue: Types.Queue): Types.SessionTracker
	local sessions: { [Player]: Types.SessionInfo } = {}
	local connections: { RBXScriptConnection } = {}

	local function onJoin(player: Player)
		if sessions[player] then
			return
		end
		local userId = UserId.normalize(player.UserId)
		if not userId then
			return
		end
		if UserId.isStudioTest(userId) then
			Log.debug(`Studio test player {player.Name} (UserId {player.UserId}) sent as userId {userId}`)
		end
		local joinSource = Session.buildJoinSource(joinData(player))
		local info: Types.SessionInfo = {
			sessionId = Uuid(),
			userId = userId,
			startedAt = Clock(),
			launchCode = joinSource.launchCode,
		}
		sessions[player] = info

		local joinTs = info.startedAt
		-- Country lookup yields; emit player_join once it resolves.
		task.spawn(function()
			local ok, err = pcall(function()
				info.country = country(player)
				queue:push({
					id = Uuid(),
					type = "player_join",
					ts = joinTs,
					userId = info.userId,
					sessionId = info.sessionId,
					data = {
						country = info.country,
						premium = player.MembershipType == Enum.MembershipType.Premium,
						accountAgeDays = math.max(0, math.floor(player.AccountAge)),
						joinSource = joinSource,
					},
				})
			end)
			if not ok then
				Log.warn(`player_join failed: {err}`)
			end
		end)
	end

	-- Sessions whose player_leave was already sent (PlayerRemoving or shutdown, whichever is first).
	local ended: { [Types.SessionInfo]: boolean } = setmetatable({}, { __mode = "k" }) :: any

	local function onLeave(player: Player)
		local info = sessions[player]
		if not info or ended[info] then
			return
		end
		ended[info] = true
		queue:push({
			id = Uuid(),
			type = "player_leave",
			ts = Clock(),
			userId = info.userId,
			sessionId = info.sessionId,
			data = { durationS = math.max(0, math.floor((Clock() - info.startedAt) / 1000)) },
		})
		task.delay(Session.RETAIN_AFTER_LEAVE_S, function()
			if sessions[player] == info then
				sessions[player] = nil
			end
		end)
	end

	local function guarded(label: string, fn: (Player) -> ()): (Player) -> ()
		return function(player: Player)
			local ok, err = pcall(function()
				fn(player)
			end)
			if not ok then
				Log.warn(`{label} failed: {err}`)
			end
		end
	end

	table.insert(connections, Players.PlayerAdded:Connect(guarded("PlayerAdded", onJoin)))
	table.insert(connections, Players.PlayerRemoving:Connect(guarded("PlayerRemoving", onLeave)))
	-- Players who joined before init (e.g. init after a yield).
	for _, player in Players:GetPlayers() do
		task.spawn(guarded("PlayerAdded", onJoin), player)
	end
	-- On shutdown PlayerRemoving may fire late (or not before the process dies), so close every live
	-- session here without yielding. Bound before Server's BindToClose (init order), so these
	-- player_leave events are queued ahead of server_stop and go out in the final flush.
	game:BindToClose(function()
		for player in sessions do
			guarded("BindToClose", onLeave)(player)
		end
	end)

	local tracker = {}

	function tracker.get(_self: any, player: Player): Types.SessionInfo?
		return sessions[player]
	end

	function tracker.destroy(_self: any)
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		table.clear(sessions)
	end

	Log.debug("session tracking started")
	return (tracker :: any) :: Types.SessionTracker
end

return Session

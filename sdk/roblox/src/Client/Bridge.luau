--!strict
--[[
	Server side of the optional client module.

	* Creates (or reuses) RemoteEvent `ReplicatedStorage.RoMetricsClient`.
	* Installs the bundled `RoMetricsClient` LocalScript into StarterPlayerScripts when it is not
	  there yet (players that joined before `init` do not get it).
	* Accepts ONE valid report per player session; everything else is ignored. Payload:
	  { platform = "desktop"|"mobile"|"tablet"|"console"|"vr"|"unknown", screenW?, screenH? }.
	* Emits `player_platform` and stores the platform on the SessionInfo.
]]

local Types = require(script.Parent.Parent.Types)
local Log = require(script.Parent.Parent.Util.Log)
local Uuid = require(script.Parent.Parent.Util.Uuid)
local Clock = require(script.Parent.Parent.Util.Clock)

export type Deps = {
	replicatedStorage: any,
	players: any,
	starterPlayerScripts: any?,
	-- Bundled LocalScript to install (nil = do not install).
	clientScript: any?,
	-- Seconds to wait for a session to appear after the report arrives.
	sessionWait: number?,
}

local REMOTE_NAME = "RoMetricsClient"
local MAX_SCREEN = 16384
local SESSION_POLL_S = 0.5

local PLATFORMS: { [string]: boolean } = {
	desktop = true,
	mobile = true,
	tablet = true,
	console = true,
	vr = true,
	unknown = true,
}

export type Report = { platform: string, screenW: number?, screenH: number? }

local Bridge = {}

local function screenDim(value: unknown): number?
	if type(value) ~= "number" or value ~= value or value < 0 or value > MAX_SCREEN then
		return nil
	end
	return math.floor(value)
end

-- Validates an untrusted client payload. Pure; unit tested.
function Bridge.parseReport(payload: unknown): Report?
	if type(payload) ~= "table" then
		return nil
	end
	local raw = payload :: { [unknown]: unknown }
	local platform = raw.platform
	if type(platform) ~= "string" or not PLATFORMS[platform] then
		return nil
	end
	return {
		platform = platform,
		screenW = screenDim(raw.screenW),
		screenH = screenDim(raw.screenH),
	}
end

local function defaultDeps(): Deps
	local starterPlayer = game:GetService("StarterPlayer")
	return {
		replicatedStorage = game:GetService("ReplicatedStorage"),
		players = game:GetService("Players"),
		starterPlayerScripts = starterPlayer:FindFirstChildOfClass("StarterPlayerScripts"),
		clientScript = script.Parent:FindFirstChild("RoMetricsClient"),
		sessionWait = 10,
	}
end

local function getRemote(replicatedStorage: any): any
	local existing = replicatedStorage:FindFirstChild(REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = REMOTE_NAME
	remote.Parent = replicatedStorage
	return remote
end

local function installClientScript(deps: Deps)
	local source = deps.clientScript
	local target = deps.starterPlayerScripts
	if not source or not target then
		return
	end
	-- A Script with RunContext=Client already runs from ReplicatedStorage; only LocalScripts need copying.
	if not source:IsA("LocalScript") then
		return
	end
	if target:FindFirstChild(source.Name) then
		return
	end
	local clone = source:Clone()
	clone.Parent = target
end

-- Returns a disconnect function (used by tests).
function Bridge.start(
	_config: Types.Config,
	queue: Types.Queue,
	sessions: Types.SessionTracker,
	overrides: Deps?
): () -> ()
	local deps = overrides or defaultDeps()
	local remote = getRemote(deps.replicatedStorage)

	local ok, err = pcall(function()
		installClientScript(deps)
	end)
	if not ok then
		Log.warn(`could not install client script: {err}`)
	end

	-- Players whose report was accepted (or is being processed) this session.
	local handled: { [any]: boolean } = {}
	local sessionWait = deps.sessionWait or 10

	local function onReport(player: Player, payload: unknown)
		if handled[player] then
			return
		end
		local report = Bridge.parseReport(payload)
		if not report then
			Log.debug(`invalid client report from {player.UserId}`)
			return
		end
		handled[player] = true
		-- The session may still be initializing (join data / country lookups yield).
		local session = sessions:get(player)
		local waited = 0
		while not session and waited < sessionWait and player.Parent ~= nil do
			task.wait(SESSION_POLL_S)
			waited += SESSION_POLL_S
			session = sessions:get(player)
		end
		if not session then
			Log.debug(`client report from {player.UserId} dropped: no session`)
			return
		end
		session.platform = report.platform
		local data: { [string]: any } = { platform = report.platform }
		data.screenW = report.screenW
		data.screenH = report.screenH
		queue:push({
			id = Uuid(),
			type = "player_platform",
			ts = Clock(),
			userId = session.userId,
			sessionId = session.sessionId,
			data = data,
		})
	end

	local eventConnection = remote.OnServerEvent:Connect(function(player: Player, payload: unknown)
		local handledOk, handledErr = pcall(function()
			onReport(player, payload)
		end)
		if not handledOk then
			Log.warn(`client report failed: {handledErr}`)
		end
	end)
	local leaveConnection = deps.players.PlayerRemoving:Connect(function(player: Player)
		handled[player] = nil
	end)

	return function()
		eventConnection:Disconnect()
		leaveConnection:Disconnect()
	end
end

return Bridge

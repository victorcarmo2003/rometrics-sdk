--!strict
-- server_start, heartbeat loop, server_stop + BindToClose flushSync.
local Players = game:GetService("Players")

local Types = require(script.Parent.Types)
local Uuid = require(script.Parent.Util.Uuid)
local Clock = require(script.Parent.Util.Clock)
local Log = require(script.Parent.Util.Log)

local Server = {}

-- Seconds BindToClose waits for the final flush (Roblox gives ~30 s total).
Server.SHUTDOWN_FLUSH_S = 25

-- Captured when the module first loads (i.e. at SDK require time, close to server start).
local startedAt: number = Clock()
local startedClock: number = os.clock()
-- Studio runs have an empty JobId; the ingest schema requires a non-empty one.
local studioJobId: string? = nil

local started = false

local function uptimeS(): number
	return math.max(0, math.floor(os.clock() - startedClock))
end

local function event(kind: string, data: { [string]: any }?): Types.Event
	return { id = Uuid(), type = kind, ts = Clock(), data = data }
end

-- Server metadata attached to every batch envelope (used by Transport).
function Server.info(): Types.ServerInfo
	local jobId = game.JobId
	if jobId == "" then
		if not studioJobId then
			studioJobId = `studio-{Uuid()}`
		end
		jobId = studioJobId :: string
	end
	return {
		universeId = game.GameId,
		placeId = game.PlaceId,
		placeVersion = game.PlaceVersion,
		jobId = jobId,
		private = game.PrivateServerId ~= "",
		startedAt = startedAt,
	}
end

function Server.start(config: Types.Config, queue: Types.Queue)
	if started then
		return
	end
	started = true

	queue:push(event("server_start", {
		private = game.PrivateServerId ~= "",
		privateServerOwnerId = if game.PrivateServerOwnerId ~= 0 then game.PrivateServerOwnerId else nil,
	}))

	task.spawn(function()
		while true do
			task.wait(config.heartbeatInterval)
			local ok, err = pcall(function()
				queue:push(event("heartbeat", {
					players = #Players:GetPlayers(),
					maxPlayers = Players.MaxPlayers,
					fps = math.floor(workspace:GetRealPhysicsFPS() * 10 + 0.5) / 10,
					uptimeS = uptimeS(),
					dropped = queue:stats().dropped,
				}))
			end)
			if not ok then
				Log.warn(`heartbeat failed: {err}`)
			end
		end
	end)

	local closed = false
	game:BindToClose(function()
		if closed then
			return
		end
		closed = true
		local ok, err = pcall(function()
			queue:push(event("server_stop", { uptimeS = uptimeS() }))
			queue:flushSync(Server.SHUTDOWN_FLUSH_S)
		end)
		if not ok then
			Log.warn(`shutdown flush failed: {err}`)
		end
	end)
end

return Server

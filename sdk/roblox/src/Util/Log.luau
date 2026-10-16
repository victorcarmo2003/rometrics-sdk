--!strict
-- Output logging with a fixed prefix; debug lines are gated by config.debug.
local PREFIX = "[RoMetrics]"

local Log = {}

local debugEnabled = false

function Log.setDebug(enabled: boolean)
	debugEnabled = enabled == true
end

function Log.isDebug(): boolean
	return debugEnabled
end

function Log.info(msg: string)
	print(`{PREFIX} {msg}`)
end

function Log.warn(msg: string)
	warn(`{PREFIX} {msg}`)
end

function Log.debug(msg: string)
	if debugEnabled then
		print(`{PREFIX} [debug] {msg}`)
	end
end

return Log

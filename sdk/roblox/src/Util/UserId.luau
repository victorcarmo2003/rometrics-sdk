--!strict
-- Wire-safe user ids. Studio "local server" test players have UserId <= 0 (Player1 = -1, Player2 = -2),
-- which the ingest rejects (userId must be a non-negative integer). They are mapped to a reserved
-- synthetic range far above real Roblox ids, so Studio tests still produce sessions and events
-- without colliding with real players.
local UserId = {}

-- 1e13: ~1000x above current real ids and still exact with 14-significant-digit JSON encoders.
UserId.STUDIO_TEST_BASE = 10_000_000_000_000

-- Returns the id to send for `userId`, or nil when it is not a number. Pure; unit tested.
function UserId.normalize(userId: unknown): number?
	if typeof(userId) ~= "number" or userId ~= userId then
		return nil
	end
	local n = math.floor(userId :: number)
	if n > 0 then
		return n
	end
	return UserId.STUDIO_TEST_BASE + math.abs(n)
end

function UserId.isStudioTest(userId: number): boolean
	return userId >= UserId.STUDIO_TEST_BASE
end

return UserId

--!strict
--[[
	RoMetrics optional client reporter.

	LocalScript for StarterPlayerScripts. `RoMetrics.init` installs it automatically; copy it
	manually only if you load the SDK somewhere it cannot reach StarterPlayerScripts.
	Sends ONE report per session through RemoteEvent `ReplicatedStorage.RoMetricsClient`:
	platform + screen size. The server validates and ignores anything after the first report.
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local VRService = game:GetService("VRService")

local REMOTE_NAME = "RoMetricsClient"
local REMOTE_TIMEOUT_S = 60
-- Shorter screen side (in points) from which a touch device counts as a tablet.
local TABLET_MIN_SIDE = 600

local function viewportSize(): Vector2
	local camera = workspace.CurrentCamera
	local waited = 0
	-- The viewport reports 1x1 for a few frames after join.
	while (not camera or camera.ViewportSize.X <= 1) and waited < 5 do
		task.wait(0.25)
		waited += 0.25
		camera = workspace.CurrentCamera
	end
	return if camera then camera.ViewportSize else Vector2.zero
end

local function detectPlatform(size: Vector2): string
	if VRService.VREnabled then
		return "vr"
	end
	if GuiService:IsTenFootInterface() then
		return "console"
	end
	local touch = UserInputService.TouchEnabled
	local keyboard = UserInputService.KeyboardEnabled
	local gamepad = UserInputService.GamepadEnabled
	if touch and not keyboard then
		local shortSide = math.min(size.X, size.Y)
		return if shortSide >= TABLET_MIN_SIDE then "tablet" else "mobile"
	end
	if gamepad and not keyboard then
		return "console"
	end
	if keyboard then
		return "desktop"
	end
	return "unknown"
end

local ok, err = pcall(function()
	local remote = ReplicatedStorage:WaitForChild(REMOTE_NAME, REMOTE_TIMEOUT_S)
	if remote and remote:IsA("RemoteEvent") then
		local size = viewportSize()
		remote:FireServer({
			platform = detectPlatform(size),
			screenW = math.floor(size.X),
			screenH = math.floor(size.Y),
		})
	end
end)
if not ok then
	warn(`[RoMetrics] client report failed: {err}`)
end

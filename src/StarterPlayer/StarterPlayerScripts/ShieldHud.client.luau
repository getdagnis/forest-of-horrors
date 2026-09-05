-- ShieldHud
-- Reads the server-owned ShieldExpiresAt attribute and presents the remaining
-- protection time directly below the local battle radar.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "ShieldStatusHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local label = Instance.new("TextLabel")
label.Name = "ShieldTimer"
label.AnchorPoint = Vector2.new(1, 0)
label.Size = UDim2.fromOffset(152, 28)
label.BackgroundColor3 = Color3.fromRGB(8, 22, 34)
label.BackgroundTransparency = 0.18
label.BorderSizePixel = 0
label.Font = Enum.Font.GothamBold
label.TextColor3 = Color3.fromRGB(152, 233, 255)
label.TextStrokeTransparency = 0.68
label.TextSize = 32
label.Visible = false
label.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 4)
corner.Parent = label
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(86, 187, 225)
stroke.Transparency = 0.5
stroke.Parent = label

local function placeBelowRadar()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local mobile = viewport.X < 1100 or viewport.Y < 650
	-- Match ScoreGui's rank value: 32px desktop, 16px compact/mobile.
	label.TextSize = mobile and 16 or 32
	label.Size = mobile and UDim2.fromOffset(152, 28) or UDim2.fromOffset(210, 44)
	local radarHud = playerGui:FindFirstChild("MonsterRadarHud")
	local radar = radarHud and radarHud:FindFirstChild("Radar")
	if radar and radar:IsA("GuiObject") and radar.AbsoluteSize.Y > 0 then
		label.Position = UDim2.fromOffset(
			radar.AbsolutePosition.X + radar.AbsoluteSize.X,
			radar.AbsolutePosition.Y + radar.AbsoluteSize.Y + 8
		)
	else
		-- MonsterRadar can be a frame late during character startup.
		label.Position = UDim2.new(1, -12, 0, 208)
	end
end

local function update()
	local expiresAt = tonumber(player:GetAttribute("ShieldExpiresAt"))
	local remaining = expiresAt and math.max(0, expiresAt - workspace:GetServerTimeNow()) or 0
	label.Visible = remaining > 0
	if not label.Visible then return end
	local totalSeconds = math.ceil(remaining)
	label.Text = string.format("SHIELD  %d:%02d", math.floor(totalSeconds / 60), totalSeconds % 60)
	placeBelowRadar()
end

player:GetAttributeChangedSignal("ShieldExpiresAt"):Connect(update)
local updateElapsed = 0
RunService.Heartbeat:Connect(function(deltaTime)
	-- A tenth of a second keeps the timer smooth without adding a per-frame HUD
	-- update to an already busy monster round.
	updateElapsed += deltaTime
	if updateElapsed < 0.1 then return end
	updateElapsed = 0
	update()
end)
update()

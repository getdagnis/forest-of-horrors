-- ShieldHud
-- Reads the server-owned ShieldExpiresAt attribute and presents the remaining
-- protection time directly below ScoreGui's top-right combat score bar.

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
label.TextSize = 16
label.Visible = false
label.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 4)
corner.Parent = label
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(86, 187, 225)
stroke.Transparency = 0.5
stroke.Parent = label

local function placeBelowScorebar()
	local combatHud = playerGui:FindFirstChild("CombatStatusHud")
	local bar = combatHud and combatHud:FindFirstChild("CombatStatusBar")
	if bar and bar:IsA("GuiObject") and bar.AbsoluteSize.Y > 0 then
		label.Position = UDim2.fromOffset(
			bar.AbsolutePosition.X + bar.AbsoluteSize.X,
			bar.AbsolutePosition.Y + bar.AbsoluteSize.Y + 8
		)
	else
		-- ScoreGui can be a frame late during character startup.
		label.Position = UDim2.new(1, -24, 0, 104)
	end
end

local function update()
	local expiresAt = tonumber(player:GetAttribute("ShieldExpiresAt"))
	local remaining = expiresAt and math.max(0, expiresAt - workspace:GetServerTimeNow()) or 0
	label.Visible = remaining > 0
	if not label.Visible then return end
	local totalSeconds = math.ceil(remaining)
	label.Text = string.format("SHIELD  %d:%02d", math.floor(totalSeconds / 60), totalSeconds % 60)
	placeBelowScorebar()
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

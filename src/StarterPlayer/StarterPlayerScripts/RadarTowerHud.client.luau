-- RadarTowerHud: client-only tactical display for the author-owned pilot console.
-- It reads the same MonsterManager definitions used by gameplay; no duplicate
-- monster lists or server bookkeeping are needed for its live contacts.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local useEvent = ReplicatedStorage:WaitForChild("RadarTowerUse")
local snapshotEvent = ReplicatedStorage:WaitForChild("RadarTowerSnapshot")

-- Tune this to the loop's real beep interval if its audio is trimmed later.
local PULSE_INTERVAL = 2.0
-- The tower is a tactical snapshot rather than a live GPS feed.
local REFRESH_INTERVAL = 10.0
local AMBIENT_RANGE = 30
local AMBIENT_UPDATE_INTERVAL = 0.4
local TOP_THREAT_TYPES = 4
local RADAR_VALUE_FONT_SIZE = 16
local RADAR_DETAIL_FONT_SIZE = 8
-- Only Drooling Zombies use the compact battle-radar contact size. Other
-- hostiles retain the larger tower-radar contact size for quick triage.
local ZOMBIE_NAME = "Drooling Zombie"
local ZOMBIE_DOT_SIZE = 6
local HOSTILE_DOT_SIZE = 10
local SECRET_SHAFT_GUARDIAN_DOT_SIZE = 8
local MCDONALDS_LOGO_IMAGE = "rbxassetid://102275809524944"

local COLORS = {
	background = Color3.fromRGB(8, 3, 18),
	panel = Color3.fromRGB(25, 12, 46),
	map = Color3.fromRGB(13, 7, 28),
	phosphor = Color3.fromRGB(198, 117, 255),
	cyan = Color3.fromRGB(157, 129, 255),
	threat = Color3.fromRGB(255, 52, 117),
	monsterGun1 = Color3.fromRGB(255, 105, 180),
	friendly = Color3.fromRGB(186, 180, 203),
	guardian = Color3.fromRGB(220, 240, 210),
	text = Color3.fromRGB(244, 235, 255),
	muted = Color3.fromRGB(181, 153, 213),
}

warn("[RadarTowerHud] client started; waiting for RadarTowerUse")

local function makeFrame(name, parent, color, transparency)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function makeText(name, parent, text, size, color, font)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color or COLORS.text
	label.Font = font or Enum.Font.Montserrat
	label.TextSize = size
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	return label
end

local gui = Instance.new("ScreenGui")
gui.Name = "RadarTowerHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")
player:SetAttribute("RadarHudOpen", false)

local shade = makeFrame("Shade", gui, COLORS.background, 0.14)
shade.Size = UDim2.fromScale(1, 1)

local panel = makeFrame("NightwatchTacticalRadar", shade, COLORS.panel, 0.08)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.52)
panel.Size = UDim2.fromScale(0.92, 0.88)
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COLORS.phosphor
panelStroke.Transparency = 0.45
panelStroke.Thickness = 1
panelStroke.Parent = panel

local title = makeText("Title", panel, "NIGHTWATCH MONSTER RADAR", 28, COLORS.text, Enum.Font.MontserratBold)
title.Position = UDim2.fromOffset(28, 13)
title.Size = UDim2.new(1, -210, 0, 37)

local subtitle = makeText("Subtitle", panel, "DARK FOREST DEFENSE NETWORK  /  LIVE BIOLOGICAL UPLINK", RADAR_DETAIL_FONT_SIZE, COLORS.muted)
subtitle.Position = UDim2.fromOffset(30, 46)
subtitle.Size = UDim2.new(1, -240, 0, 22)

local close = Instance.new("TextButton")
close.Name = "Exit"
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -24, 0, 18)
close.Size = UDim2.fromOffset(110, 42)
close.BackgroundColor3 = COLORS.background
close.BackgroundTransparency = 0.35
close.BorderSizePixel = 0
close.Text = "EXIT"
close.TextColor3 = COLORS.text
close.TextSize = RADAR_DETAIL_FONT_SIZE
close.Font = Enum.Font.MontserratBold
close.Active = true
close.Selectable = true
close.Modal = true
close.ZIndex = 20
close.Parent = panel
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 4)
local closeStroke = Instance.new("UIStroke")
closeStroke.Color = COLORS.muted
closeStroke.Transparency = 0.45
closeStroke.Parent = close

local stats = Instance.new("Frame")
stats.Name = "StatusStrip"
stats.BackgroundTransparency = 1
stats.Position = UDim2.fromOffset(28, 79)
stats.Size = UDim2.new(1, -56, 0, 51)
stats.Parent = panel

local statValues = {}
local statCards = {}
local statCaptions = {}
local function addStat(index, caption, accent)
	local card = makeFrame("Stat", stats, COLORS.background, 0.38)
	card.Position = UDim2.new((index - 1) * 0.25, index == 1 and 0 or 4, 0, 0)
	card.Size = UDim2.new(0.25, index == 1 and -3 or -4, 1, 0)
	statCards[index] = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
	stroke.Transparency = 0.67
	stroke.Parent = card
	local captionLabel = makeText("Caption", card, caption, RADAR_DETAIL_FONT_SIZE, COLORS.muted)
	captionLabel.Position = UDim2.fromOffset(11, 4)
	captionLabel.Size = UDim2.new(1, -22, 0, 17)
	statCaptions[index] = captionLabel
	local value = makeText("Value", card, "--", RADAR_VALUE_FONT_SIZE, accent, Enum.Font.MontserratBold)
	value.Position = UDim2.fromOffset(11, 19)
	value.Size = UDim2.new(1, -22, 0, 27)
	statValues[caption] = value
end

-- This is a live client contact count (the dots on this map), deliberately
-- distinct from ScoreGui's server-authoritative round ledger.
addStat(1, "CONTACTS", COLORS.threat)
addStat(2, "SURVIVORS", COLORS.friendly)
addStat(3, "BEACONS", COLORS.cyan)
addStat(4, "SCAN RATE", COLORS.phosphor)

local plot = makeFrame("Map", panel, COLORS.map, 0.04)
plot.Position = UDim2.fromOffset(28, 145)
plot.Size = UDim2.new(1, -56, 1, -190)
plot.ClipsDescendants = true
local plotStroke = Instance.new("UIStroke")
plotStroke.Color = COLORS.cyan
plotStroke.Transparency = 0.57
plotStroke.Thickness = 1
plotStroke.Parent = plot

-- Fine grid gives map precision; brighter five-square divisions retain a
-- readable military-map hierarchy at a glance.
for column = 1, 24 - 1 do
	local major = column % 4 == 0
	local line = makeFrame("GridV", plot, COLORS.phosphor, major and 0.73 or 0.89)
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.fromScale(column / 24, 0)
	line.Size = UDim2.new(0, major and 1 or 1, 1, 0)
end
for row = 1, 16 - 1 do
	local major = row % 4 == 0
	local line = makeFrame("GridH", plot, COLORS.phosphor, major and 0.73 or 0.89)
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.Position = UDim2.fromScale(0, row / 16)
	line.Size = UDim2.new(1, 0, 0, major and 1 or 1)
end

local horizontalAxis = makeFrame("AxisH", plot, COLORS.cyan, 0.60)
horizontalAxis.AnchorPoint = Vector2.new(0, 0.5)
horizontalAxis.Position = UDim2.fromScale(0, 0.5)
horizontalAxis.Size = UDim2.new(1, 0, 0, 1)
local verticalAxis = makeFrame("AxisV", plot, COLORS.cyan, 0.60)
verticalAxis.AnchorPoint = Vector2.new(0.5, 0)
verticalAxis.Position = UDim2.fromScale(0.5, 0)
verticalAxis.Size = UDim2.new(0, 1, 1, 0)

local sweep = makeFrame("Sweep", plot, COLORS.phosphor, 0.82)
sweep.AnchorPoint = Vector2.new(0, 0)
sweep.Position = UDim2.fromScale(-0.08, 0)
sweep.Size = UDim2.fromScale(0.08, 1)
local sweepGradient = Instance.new("UIGradient")
sweepGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.74, 0.70),
	NumberSequenceKeypoint.new(1, 0.12),
})
sweepGradient.Parent = sweep

local landmarkLayer = Instance.new("Folder")
landmarkLayer.Name = "Landmarks"
landmarkLayer.Parent = plot
local contourLayer = Instance.new("Folder")
contourLayer.Name = "WorldLandmarks"
contourLayer.Parent = plot
local monsterLayer = Instance.new("Folder")
monsterLayer.Name = "Monsters"
monsterLayer.Parent = plot
local playerLayer = Instance.new("Folder")
playerLayer.Name = "OtherPlayers"
playerLayer.Parent = plot

local mcdonaldsLogoMarker = Instance.new("ImageLabel")
mcdonaldsLogoMarker.Name = "McDonaldsLogo"
mcdonaldsLogoMarker.AnchorPoint = Vector2.new(0.5, 0.5)
mcdonaldsLogoMarker.Size = UDim2.fromOffset(30, 30)
mcdonaldsLogoMarker.BackgroundTransparency = 1
mcdonaldsLogoMarker.Image = MCDONALDS_LOGO_IMAGE
mcdonaldsLogoMarker.ScaleType = Enum.ScaleType.Fit
mcdonaldsLogoMarker.ZIndex = 5
mcdonaldsLogoMarker.Visible = false
mcdonaldsLogoMarker.Parent = plot

local selfMarker = makeFrame("You", plot, COLORS.text, 0)
selfMarker.AnchorPoint = Vector2.new(0.5, 0.5)
selfMarker.Size = UDim2.fromOffset(14, 14)
Instance.new("UICorner", selfMarker).CornerRadius = UDim.new(1, 0)
local selfStroke = Instance.new("UIStroke")
selfStroke.Color = COLORS.phosphor
selfStroke.Thickness = 2
selfStroke.Parent = selfMarker
local selfLabel = makeText("PlayerName", plot, "YOU", 20, COLORS.cyan, Enum.Font.MontserratBold)
selfLabel.AnchorPoint = Vector2.new(0, 0.5)
selfLabel.Size = UDim2.fromOffset(90, 16)
selfLabel.TextXAlignment = Enum.TextXAlignment.Left
selfLabel.ZIndex = 4

local threatReadout = makeFrame("ThreatReadout", plot, COLORS.background, 0.29)
threatReadout.Position = UDim2.fromOffset(12, 12)
threatReadout.Size = UDim2.fromOffset(230, 26 + TOP_THREAT_TYPES * 19)
local threatStroke = Instance.new("UIStroke")
threatStroke.Color = COLORS.threat
threatStroke.Transparency = 0.58
threatStroke.Parent = threatReadout
local threatTitle = makeText("Title", threatReadout, "THREAT MIX // LIVE", RADAR_DETAIL_FONT_SIZE, COLORS.threat, Enum.Font.MontserratBold)
threatTitle.Position = UDim2.fromOffset(9, 3)
threatTitle.Size = UDim2.new(1, -18, 0, 19)
local threatRows = {}
for index = 1, TOP_THREAT_TYPES do
	local row = makeText("Threat" .. index, threatReadout, "", 11, COLORS.text)
	row.Position = UDim2.fromOffset(9, 21 + (index - 1) * 19)
	row.Size = UDim2.new(1, -18, 0, 19)
	threatRows[index] = row
end

local rangeReadout = makeText("RangeReadout", plot, "GRID 24 x 16  //  NORTH ↑", 11, COLORS.muted)
rangeReadout.AnchorPoint = Vector2.new(1, 1)
rangeReadout.Position = UDim2.new(0.5, 0, 1, -9)
rangeReadout.Size = UDim2.fromOffset(245, 22)
rangeReadout.TextXAlignment = Enum.TextXAlignment.Center

local cornerCoordinates = {}
local function makeCornerCoordinate(name, anchorPoint, position, alignment)
	local label = makeText(name, plot, "", RADAR_DETAIL_FONT_SIZE, COLORS.muted, Enum.Font.Montserrat)
	label.AnchorPoint = anchorPoint
	label.Position = position
	label.Size = UDim2.fromOffset(190, 18)
	label.TextXAlignment = alignment
	label.ZIndex = 3
	cornerCoordinates[name] = label
	return label
end

-- The threat panel owns the upper-left corner. Keep the other three corners
-- explicit so map orientation and bounds can be checked directly in Studio.
makeCornerCoordinate("CoordTopRight", Vector2.new(1, 0), UDim2.new(1, -12, 0, 10), Enum.TextXAlignment.Right)
makeCornerCoordinate("CoordBottomLeft", Vector2.new(0, 1), UDim2.new(0, 12, 1, -9), Enum.TextXAlignment.Left)
makeCornerCoordinate("CoordBottomRight", Vector2.new(1, 1), UDim2.new(1, -12, 1, -9), Enum.TextXAlignment.Right)

local footer = makeText("Footer", panel, "LIVE UPLINK  //  CONTACTS = LIVE DOTS  /  SCOREBAR = ROUND LEDGER", RADAR_DETAIL_FONT_SIZE, COLORS.muted)
footer.Position = UDim2.new(0, 29, 1, -38)
footer.Size = UDim2.new(1, -58, 0, 20)

-- ScoreGui uses 16px values on compact layouts. Keep the radar title larger,
-- but let everything else collapse into the same readable scale on phones.
local function applyResponsiveLayout()
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local mobile = viewport.X < 900 or viewport.Y < 600

	panel.Size = mobile and UDim2.fromScale(0.96, 0.94) or UDim2.fromScale(0.92, 0.88)
	title.Position = mobile and UDim2.fromOffset(18, 10) or UDim2.fromOffset(28, 13)
	title.Size = mobile and UDim2.new(1, -130, 0, 32) or UDim2.new(1, -210, 0, 37)
	title.TextSize = mobile and 20 or 28

	subtitle.Visible = not mobile
	close.Position = mobile and UDim2.new(1, -12, 0, 10) or UDim2.new(1, -24, 0, 18)
	close.Size = mobile and UDim2.fromOffset(104, 38) or UDim2.fromOffset(124, 44)
	close.TextSize = RADAR_VALUE_FONT_SIZE

	stats.Position = mobile and UDim2.fromOffset(18, 52) or UDim2.fromOffset(28, 79)
	stats.Size = mobile and UDim2.new(1, -36, 0, 34) or UDim2.new(1, -56, 0, 51)
	for index, card in ipairs(statCards) do
		local caption = statCaptions[index]
		local value = statValues[( { "CONTACTS", "SURVIVORS", "BEACONS", "SCAN RATE" } )[index]]
		if mobile then
			card.Position = UDim2.new((index - 1) * 0.25, index == 1 and 0 or 2, 0, 0)
			card.Size = UDim2.new(0.25, index == 1 and -2 or -3, 1, 0)
			caption.Position = UDim2.fromOffset(52, 8)
			caption.Size = UDim2.new(1, -56, 0, 16)
			caption.TextSize = RADAR_DETAIL_FONT_SIZE
			value.Position = UDim2.fromOffset(6, 0)
			value.Size = UDim2.new(0, 46, 0, 22)
			value.TextSize = RADAR_VALUE_FONT_SIZE
		else
			card.Position = UDim2.new((index - 1) * 0.25, index == 1 and 0 or 4, 0, 0)
			card.Size = UDim2.new(0.25, index == 1 and -3 or -4, 1, 0)
			caption.Position = UDim2.fromOffset(11, 4)
			caption.Size = UDim2.new(1, -22, 0, 17)
			caption.TextSize = RADAR_DETAIL_FONT_SIZE
			value.Position = UDim2.fromOffset(11, 18)
			value.Size = UDim2.new(1, -22, 0, 29)
			value.TextSize = RADAR_VALUE_FONT_SIZE
		end
	end

	plot.Position = mobile and UDim2.fromOffset(18, 89) or UDim2.fromOffset(28, 145)
	plot.Size = mobile and UDim2.new(1, -36, 1, -89) or UDim2.new(1, -56, 1, -190)
	threatReadout.Visible = not mobile
	threatReadout.Size = mobile and UDim2.fromOffset(196, 26 + TOP_THREAT_TYPES * 18) or UDim2.fromOffset(230, 26 + TOP_THREAT_TYPES * 19)
	threatTitle.TextSize = RADAR_DETAIL_FONT_SIZE
	for _, row in ipairs(threatRows) do row.TextSize = RADAR_DETAIL_FONT_SIZE end
	rangeReadout.TextSize = mobile and 9 or 12
	rangeReadout.Size = mobile and UDim2.fromOffset(175, 18) or UDim2.fromOffset(245, 22)
	for _, label in pairs(cornerCoordinates) do
		label.TextSize = mobile and 8 or 10
		label.Size = mobile and UDim2.fromOffset(150, 16) or UDim2.fromOffset(190, 18)
	end
	footer.Position = mobile and UDim2.new(0, 19, 1, -27) or UDim2.new(0, 29, 1, -38)
	footer.Size = mobile and UDim2.new(1, -38, 0, 16) or UDim2.new(1, -58, 0, 20)
	footer.TextSize = mobile and 8 or 12
	footer.Visible = not mobile
end

applyResponsiveLayout()
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(applyResponsiveLayout)
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyResponsiveLayout)
end

local monsterDots = {}
local guardianDots = {}
local secretShaftGuardianDots = {}
local secretShaftGuardianLabels = {}
local playerDots = {}
local playerLabels = {}
local landmarkMarkers = {}
local landmarkLabels = {}
local contourSegments = {}
local activeRadarLoop
local backpackWasEnabled
local latestServerSnapshot

local function setRadarInventoryHidden(hidden)
	if hidden then
		if backpackWasEnabled == nil then
			local ok, enabled = pcall(function()
				return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
			end)
			backpackWasEnabled = ok and enabled or true
		end
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
	elseif backpackWasEnabled ~= nil then
		local restore = backpackWasEnabled
		backpackWasEnabled = nil
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, restore)
		end)
	end
end

local function mapBounds()
	local min = Workspace:GetAttribute("RadarMapMin")
	local max = Workspace:GetAttribute("RadarMapMax")
	if typeof(min) ~= "Vector3" or typeof(max) ~= "Vector3" then
		-- MainGround is the authoritative footprint when explicit map attributes
		-- have not been authored yet. This keeps edge contacts from being hidden
		-- by the old marketplace fallback bounds.
		local ground = Workspace:FindFirstChild("MainGround")
		if ground and ground:IsA("BasePart") then
			local half = ground.Size * 0.5
			min = ground.Position - half
			max = ground.Position + half
		else
			min, max = Vector3.new(-1304, 0, -1651), Vector3.new(743.5, 0, 396.5)
		end
	end
	return min, max
end

local function mapPosition(worldPosition, min, max)
	local width = math.max(1, max.X - min.X)
	local depth = math.max(1, max.Z - min.Z)
	-- Keep the familiar south-at-top vertical orientation, but restore normal
	-- west-to-east left/right ordering. The prior 180-degree rotation placed a
	-- player in the horizontally opposite corner of the map.
	local x = math.clamp((worldPosition.X - min.X) / width, 0, 1)
	local y = math.clamp((worldPosition.Z - min.Z) / depth, 0, 1)
	return UDim2.fromScale(
		x,
		y
	)
end

local function updateCornerCoordinates(min, max)
	cornerCoordinates.CoordTopRight.Text = string.format("X %.0f  /  Z %.0f", max.X, min.Z)
	cornerCoordinates.CoordBottomLeft.Text = string.format("X %.0f  /  Z %.0f", min.X, max.Z)
	cornerCoordinates.CoordBottomRight.Text = string.format("X %.0f  /  Z %.0f", max.X, max.Z)
end

local function getMonsterDot(index, isZombie)
	local dot = monsterDots[index]
	if not dot then
		dot = makeFrame("Hostile", monsterLayer, COLORS.threat, 0)
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
		monsterDots[index] = dot
	end
	local size = isZombie and ZOMBIE_DOT_SIZE or HOSTILE_DOT_SIZE
	dot.Size = UDim2.fromOffset(size, size)
	return dot
end

local function getGuardianDot(index)
	local dot = guardianDots[index]
	if dot then return dot end
	dot = makeFrame("GuardianPet", monsterLayer, COLORS.guardian, 1)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(13, 13)
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.guardian
	stroke.Thickness = 2
	stroke.Transparency = 0
	stroke.Parent = dot
	guardianDots[index] = dot
	return dot
end

local function getSecretShaftGuardianDot(index)
	local dot = secretShaftGuardianDots[index]
	if dot then return dot end
	dot = makeFrame("SecretShaftGuardian", monsterLayer, COLORS.monsterGun1, 0)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(SECRET_SHAFT_GUARDIAN_DOT_SIZE, SECRET_SHAFT_GUARDIAN_DOT_SIZE)
	dot.ZIndex = 6
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	secretShaftGuardianDots[index] = dot
	return dot
end

local function getSecretShaftGuardianLabel(index)
	local label = secretShaftGuardianLabels[index]
	if label then return label end
	label = makeText("SecretShaftGuardianName", monsterLayer, "secret shaft guardian", RADAR_VALUE_FONT_SIZE, COLORS.monsterGun1, Enum.Font.MontserratBold)
	label.AnchorPoint = Vector2.new(1, 0)
	label.Size = UDim2.fromOffset(220, 24)
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.ZIndex = 7
	secretShaftGuardianLabels[index] = label
	return label
end

local function placeSecretShaftGuardianLabel(label, position)
	-- This boss lives near the map's right edge.  Anchor the name below-left so
	-- it stays inside the map instead of clipping off its right side.
	label.Position = UDim2.new(position.X.Scale, position.X.Offset - 5, position.Y.Scale, position.Y.Offset + 6)
	label.Visible = true
end

local function getPlayerDot(index)
	local dot = playerDots[index]
	if dot then return dot end
	dot = makeFrame("Survivor", playerLayer, COLORS.friendly, 0.04)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(10, 10)
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	playerDots[index] = dot
	return dot
end

local function getPlayerLabel(index)
	local label = playerLabels[index]
	if label then return label end
	label = makeText("PlayerName", playerLayer, "", RADAR_DETAIL_FONT_SIZE, COLORS.friendly, Enum.Font.Montserrat)
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Size = UDim2.fromOffset(150, 16)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 4
	playerLabels[index] = label
	return label
end

local function getLandmark(index)
	local marker = landmarkMarkers[index]
	if marker then return marker end
	marker = makeFrame("Beacon", landmarkLayer, COLORS.cyan, 0.40)
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Rotation = 45
	marker.Size = UDim2.fromOffset(10, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.cyan
	stroke.Transparency = 0.05
	stroke.Thickness = 1
	stroke.Parent = marker
	landmarkMarkers[index] = marker
	return marker
end

local function getLandmarkLabel(index)
	local label = landmarkLabels[index]
	if label then return label end
	label = makeText("LandmarkName", landmarkLayer, "", RADAR_DETAIL_FONT_SIZE, COLORS.muted, Enum.Font.Montserrat)
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Size = UDim2.fromOffset(180, 16)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 4
	landmarkLabels[index] = label
	return label
end

local function getContourSegment(index)
	local segment = contourSegments[index]
	if segment then return segment end
	segment = makeFrame("Contour", contourLayer, COLORS.cyan, 1)
	segment.AnchorPoint = Vector2.new(0.5, 0.5)
	segment.BackgroundTransparency = 1
	segment.BorderSizePixel = 0
	segment.ZIndex = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.cyan
	stroke.Transparency = 0.16
	stroke.Thickness = 1
	stroke.Parent = segment
	contourSegments[index] = segment
	return segment
end

local function markerPosition(instance)
	if instance:IsA("BasePart") then return instance.Position end
	if instance:IsA("Model") then
		-- Imported models have unreliable pivots. A real part is the only valid
		-- landmark position for the legacy map.
		local part = instance:FindFirstChildWhichIsA("BasePart", true)
		return part and part.Position or nil
	end
	return nil
end

local function getMcDonaldsPosition()
	local landmark = Workspace:FindFirstChild("McDonald's")
		or Workspace:FindFirstChild("McDonalds")
		or Workspace:FindFirstChild("McDonaldsModel")
	return landmark and markerPosition(landmark) or nil
end

local function isRadarDetect(instance)
	-- Support both the Studio Tags editor and the older Attribute workflow.
	if CollectionService:HasTag(instance, "radar_detect")
		or CollectionService:HasTag(instance, "RadarDetect")
	then
		return true
	end
	local value = instance:GetAttribute("RadarDetect")
	if value == nil then value = instance:GetAttribute("radar_detect") end
	-- Boolean is the intended Studio attribute type. The text/number forms keep
	-- an accidental Studio attribute visible rather than silently dropping it.
	return value == true or value == "true" or value == 1
end

local function isRadarLandmark(instance)
	if CollectionService:HasTag(instance, "RadarLandmark")
		or CollectionService:HasTag(instance, "RadarContour")
	then
		return true
	end
	local value = instance:GetAttribute("RadarLandmark")
	if value == true or value == "true" or value == 1 then return true end
	-- Transitional support for the earlier contour name while Studio objects
	-- are being migrated by the command-bar conversion.
	local legacy = instance:GetAttribute("RadarContour")
	return legacy == true or legacy == "true" or legacy == 1
end

-- Key locations are shown as physical outlines rather than beacon dots.  The
-- aliases deliberately accept both the neat Studio names and the common names
-- used by imported marketplace buildings.  A building Model is processed once
-- and all of its parts form the outline, so a curved road stays curved.
local KEY_MAP_CONTOUR_NAMES = {
	["mcdonalds"] = true,
	["mcdonald"] = true,
	["applestore"] = true,
	["apple"] = true,
	["donutstore"] = true,
	["donutsstore"] = true,
	["donutshop"] = true,
	["donutsshop"] = true,
	["road"] = true,
	["roads"] = true,
	["mainroad"] = true,
}

local function normalisedMapName(name)
	return string.lower(name):gsub("[^%w]", "")
end

local function isKeyMapContour(instance)
	return instance:IsA("Model") and KEY_MAP_CONTOUR_NAMES[normalisedMapName(instance.Name)] == true
end

local function isMapContour(instance)
	-- Only explicitly authored/tagged contour objects are rendered. Inferring
	-- contours from whole building models can expand thousands of map parts into
	-- GUI segments during the first radar scan.
	return isRadarLandmark(instance)
end

local function hasMapContourAncestor(instance)
	local ancestor = instance.Parent
	while ancestor and ancestor ~= Workspace do
		if isMapContour(ancestor) then return true end
		ancestor = ancestor.Parent
	end
	return false
end


-- Keep radar work out of the open/refresh path. Imported models can have many
-- descendants, so build a yielded registry once and maintain it incrementally.
local roundMonsterModels = {}
local roundMonsterModelSet = {}
local radarCandidates = {}
local radarCandidateSet = {}

local function cacheRoundMonster(instance)
	if instance:IsA("Model")
		and not roundMonsterModelSet[instance]
		and MonsterManager.isRoundTracked(instance)
	then
		roundMonsterModelSet[instance] = true
		table.insert(roundMonsterModels, instance)
	end
end

local function isRadarCandidate(instance)
	return isRadarDetect(instance) or isMapContour(instance)
end

local function cacheRadarCandidate(instance)
	if not radarCandidateSet[instance] and isRadarCandidate(instance) then
		radarCandidateSet[instance] = true
		table.insert(radarCandidates, instance)
	end
end

local function removeCached(list, set, instance)
	if not set[instance] then return end
	set[instance] = nil
	for index = #list, 1, -1 do
		if list[index] == instance then
			table.remove(list, index)
			return
		end
	end
end

local function buildRadarRegistry()
	for index, instance in ipairs(Workspace:GetDescendants()) do
		cacheRoundMonster(instance)
		cacheRadarCandidate(instance)
		if index % 150 == 0 then
			task.wait()
		end
	end
end

Workspace.DescendantAdded:Connect(function(instance)
	cacheRoundMonster(instance)
	cacheRadarCandidate(instance)
end)

Workspace.DescendantRemoving:Connect(function(instance)
	removeCached(roundMonsterModels, roundMonsterModelSet, instance)
	removeCached(radarCandidates, radarCandidateSet, instance)
end)

-- The server snapshot is authoritative; do not scan Workspace on clients.

local function setContourSegment(segment, part, min, max)
	local width = math.max(1, max.X - min.X)
	local depth = math.max(1, max.Z - min.Z)
	local position = mapPosition(part.Position, min, max)
	local right = part.CFrame.RightVector
	local look = part.CFrame.LookVector
	local rightLength = math.max(0.002, math.sqrt((right.X * part.Size.X / width) ^ 2 + (right.Z * part.Size.X / depth) ^ 2))
	local lookLength = math.max(0.002, math.sqrt((look.X * part.Size.Z / width) ^ 2 + (look.Z * part.Size.Z / depth) ^ 2))
	local screenRightX = right.X / width
	local screenRightY = right.Z / depth
	local angle = math.deg(math.atan2(screenRightY, screenRightX))
	segment.Position = position
	segment.Size = UDim2.fromScale(rightLength, lookLength)
	segment.Rotation = angle
	segment.Visible = true
end

local function renderAuthoredContours(min, max)
	local root = Workspace:FindFirstChild("RadarContours")
	local count = 0
	if root then
		-- This is intentionally direct children only: the author-owned folder has
		-- six lightweight outline parts, never imported building descendants.
		for _, part in ipairs(root:GetChildren()) do
			if part:IsA("BasePart") then
				count += 1
				setContourSegment(getContourSegment(count), part, min, max)
			end
		end
	end
	for index = count + 1, #contourSegments do contourSegments[index].Visible = false end
end

local function displayName(instance)
	local value = instance:GetAttribute("RadarDisplayName")
	return typeof(value) == "string" and value ~= "" and value or nil
end

local function placeLabel(label, position, text)
	if not text then
		label.Visible = false
		return
	end
	label.Text = text
	label.Position = UDim2.new(position.X.Scale, 8, position.Y.Scale, 0)
	label.Visible = true
end

local function getTowerScreen(tower)
	if not (tower and tower:IsA("Model")) then return nil end
	for _, instance in ipairs(tower:GetDescendants()) do
		if instance:IsA("BasePart") and instance:GetAttribute("RadarTowerScreen") == true then
			return instance
		end
	end
	return nil
end

local function getTowerSound(tower, soundName)
	local sound = tower and tower:FindFirstChild(soundName, true)
	return sound and sound:IsA("Sound") and sound or nil
end

local function setRadarLoop(tower, enabled)
	if activeRadarLoop then activeRadarLoop:Stop() end
	activeRadarLoop = nil
	if not enabled then return end
	local radarLoop = getTowerSound(tower, "RadarLoop")
	if radarLoop then
		radarLoop:Play()
		activeRadarLoop = radarLoop
	end
end

local function updateThreatRows(typeCounts)
	local ranked = {}
	for name, count in pairs(typeCounts) do
		table.insert(ranked, { name = name, count = count })
	end
	table.sort(ranked, function(a, b)
		if a.count == b.count then return a.name < b.name end
		return a.count > b.count
	end)
	for index, row in ipairs(threatRows) do
		local entry = ranked[index]
		row.Text = entry and string.format("%02d  %s", entry.count, string.upper(entry.name)) or "--  NO CONTACT"
	end
end

local function pulseRadar()
	sweep.Position = UDim2.fromScale(-0.08, 0)
	-- One full sweep matches one audio loop, so the map centre is crossed at
	-- exactly PULSE_INTERVAL / 2 (one second for the current two-second beep).
	TweenService:Create(sweep, TweenInfo.new(PULSE_INTERVAL, Enum.EasingStyle.Linear), {
		Position = UDim2.fromScale(1, 0),
	}):Play()
	TweenService:Create(plotStroke, TweenInfo.new(PULSE_INTERVAL * 0.34), { Transparency = 0.10 }):Play()
	task.delay(PULSE_INTERVAL * 0.36, function()
		if gui.Enabled then
			TweenService:Create(plotStroke, TweenInfo.new(PULSE_INTERVAL * 0.48), { Transparency = 0.57 }):Play()
		end
	end)
end

local lastReportedBeaconCount
local function refreshRadarContacts()
	local min, max = mapBounds()
	updateCornerCoordinates(min, max)
	local monsterCount = 0
	local hostileDotCount = 0
	local guardianCount = 0
	local secretShaftGuardianCount = 0
	local playerCount = 0
	local otherPlayerDotCount = 0
	local landmarkCount = 0
	local typeCounts = {}
	local contourCount = 0
	if latestServerSnapshot then
		for _, record in ipairs(latestServerSnapshot) do
			monsterCount += 1
			typeCounts[record.name] = (typeCounts[record.name] or 0) + 1
			local mapped = mapPosition(record.position, min, max)
			if record.secretShaftGuardian then
				secretShaftGuardianCount += 1
				local guardianDot = getSecretShaftGuardianDot(secretShaftGuardianCount)
				guardianDot.Position = mapped
				guardianDot.Visible = true
				placeSecretShaftGuardianLabel(getSecretShaftGuardianLabel(secretShaftGuardianCount), mapped)
			else
				hostileDotCount += 1
				local dot = getMonsterDot(hostileDotCount, record.name == ZOMBIE_NAME)
				dot.Position = mapped
				dot.Visible = true
			end
			if record.guardian then
				guardianCount += 1
				local guardianDot = getGuardianDot(guardianCount)
				guardianDot.Position = mapped
				guardianDot.Visible = true
			end
		end
	else
	for _, instance in ipairs(roundMonsterModels) do
		if instance.Parent ~= nil
			and instance:GetAttribute("RoundManagedMonster") == true
			and (
				Workspace:GetAttribute("UndergroundPhaseActive") == true
				or instance:GetAttribute("UndergroundMonster") ~= true
			)
		then
			local humanoid = MonsterManager.getMonsterHumanoid(instance)
			-- Match the round counter's legacy-rig fallback (torso/head/primary part),
			-- rather than hiding every monster without a HumanoidRootPart.
			local monsterRoot = MonsterManager.getMonsterRoot(instance)
			if humanoid and humanoid.Health > 0 and monsterRoot then
				monsterCount += 1
				typeCounts[instance.Name] = (typeCounts[instance.Name] or 0) + 1
				local mapped = mapPosition(monsterRoot.Position, min, max)
				if instance:GetAttribute("SecretShaftDoorGuard") == true then
					secretShaftGuardianCount += 1
					local guardianDot = getSecretShaftGuardianDot(secretShaftGuardianCount)
					guardianDot.Position = mapped
					guardianDot.Visible = true
					placeSecretShaftGuardianLabel(getSecretShaftGuardianLabel(secretShaftGuardianCount), mapped)
				else
					hostileDotCount += 1
					local dot = getMonsterDot(hostileDotCount, instance.Name == ZOMBIE_NAME)
					dot.Position = mapped
					dot.Visible = true
				end
			end
		end
		if instance.Parent ~= nil
			and instance.Name == "weird monster thing"
			and instance:GetAttribute("WMTGuardianPet") == true
			and (
				Workspace:GetAttribute("UndergroundPhaseActive") == true
				or instance:GetAttribute("UndergroundMonster") ~= true
			)
		then
			local humanoid = MonsterManager.getMonsterHumanoid(instance)
			local guardianRoot = instance:FindFirstChild("HumanoidRootPart", true)
			if humanoid and humanoid.Health > 0 and guardianRoot and guardianRoot:IsA("BasePart") then
				guardianCount += 1
				local dot = getGuardianDot(guardianCount)
				dot.Position = mapPosition(guardianRoot.Position, min, max)
				dot.Visible = true
			end
		end
	end
	end
	-- Only the six author-owned parts are drawn; imported map models are never traversed.
	renderAuthoredContours(min, max)
	local mcdonaldsPosition = getMcDonaldsPosition()
	if mcdonaldsPosition then
		mcdonaldsLogoMarker.Position = mapPosition(mcdonaldsPosition, min, max)
		mcdonaldsLogoMarker.Visible = true
	else
		mcdonaldsLogoMarker.Visible = false
	end
	for _, candidate in ipairs(Players:GetPlayers()) do
		local character = candidate.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local characterRoot = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and characterRoot and characterRoot:IsA("BasePart") then
			playerCount += 1
			if candidate ~= player then
				otherPlayerDotCount += 1
				local dot = getPlayerDot(otherPlayerDotCount)
				local mapped = mapPosition(characterRoot.Position, min, max)
				dot.Position = mapped
				dot.Visible = true
				placeLabel(getPlayerLabel(otherPlayerDotCount), mapped, candidate.DisplayName or candidate.Name)
			end
		end
	end
	for index = hostileDotCount + 1, #monsterDots do monsterDots[index].Visible = false end
	for index = guardianCount + 1, #guardianDots do guardianDots[index].Visible = false end
	for index = secretShaftGuardianCount + 1, #secretShaftGuardianDots do secretShaftGuardianDots[index].Visible = false end
	for index = secretShaftGuardianCount + 1, #secretShaftGuardianLabels do secretShaftGuardianLabels[index].Visible = false end
	for index = otherPlayerDotCount + 1, #playerDots do playerDots[index].Visible = false end
	for index = otherPlayerDotCount + 1, #playerLabels do playerLabels[index].Visible = false end
	for index = landmarkCount + 1, #landmarkMarkers do landmarkMarkers[index].Visible = false end
	for index = landmarkCount + 1, #landmarkLabels do landmarkLabels[index].Visible = false end
	for index = contourCount + 1, #contourSegments do contourSegments[index].Visible = false end
	if lastReportedBeaconCount ~= landmarkCount then
		lastReportedBeaconCount = landmarkCount
		warn("[RadarTowerHud] radar_detect beacons:", landmarkCount)
	end

	statValues.CONTACTS.Text = string.format("%02d", monsterCount)
	statValues.SURVIVORS.Text = string.format("%02d", playerCount)
	statValues.BEACONS.Text = string.format("%02d", landmarkCount)
	statValues["SCAN RATE"].Text = string.format("%.2fs", REFRESH_INTERVAL)
	footer.Text = string.format(
		"LIVE UPLINK  //  SNAPSHOT %.2fs  //  CONTACTS = SNAPSHOT DOTS  /  SCOREBAR = ROUND LEDGER  /  SURVIVOR = GREY  /  BEACON = LAVENDER",
		REFRESH_INTERVAL
	)
	updateThreatRows(typeCounts)
end

local pulseElapsed = PULSE_INTERVAL
local refreshElapsed = REFRESH_INTERVAL - 0.5
RunService.Heartbeat:Connect(function(deltaTime)
	if not gui.Enabled then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	selfMarker.Visible = root ~= nil
	selfLabel.Visible = root ~= nil
	if root then
		local min, max = mapBounds()
		local mapped = mapPosition(root.Position, min, max)
		selfMarker.Position = mapped
		placeLabel(selfLabel, mapped, "YOU")
	end

	pulseElapsed += deltaTime
	if pulseElapsed >= PULSE_INTERVAL then
		pulseElapsed %= PULSE_INTERVAL
		pulseRadar()
	end
	refreshElapsed += deltaTime
	if refreshElapsed >= REFRESH_INTERVAL then
		refreshElapsed %= REFRESH_INTERVAL
		refreshRadarContacts()
	end
end)

local ambientElapsed = 0
RunService.Heartbeat:Connect(function(deltaTime)
	ambientElapsed += deltaTime
	if ambientElapsed < AMBIENT_UPDATE_INTERVAL then return end
	ambientElapsed = 0

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	for _, tower in ipairs(Workspace:GetChildren()) do
		if tower:IsA("Model") and tower:GetAttribute("RadarTower") == true then
			local yacht = getTowerSound(tower, "RadarYacht")
			local screen = getTowerScreen(tower)
			if yacht and screen and root and root:IsA("BasePart")
				and (root.Position - screen.Position).Magnitude <= AMBIENT_RANGE
			then
				if not yacht.IsPlaying then yacht:Play() end
			elseif yacht and yacht.IsPlaying then
				yacht:Stop()
			end
		end
	end
end)

local function exitRadar()
	gui.Enabled = false
	player:SetAttribute("RadarHudOpen", false)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	setRadarLoop(nil, false)
	setRadarInventoryHidden(false)
	useEvent:FireServer(false)
end

close.Activated:Connect(exitRadar)
UserInputService.InputBegan:Connect(function(input, processed)
	-- Escape can be marked processed by Roblox's core UI. E can be marked
	-- processed by an equipped Tool, but both are unambiguous modal exits here.
	if gui.Enabled and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.E) then
		exitRadar()
	end
end)

useEvent.OnClientEvent:Connect(function(enabled, tower)
	gui.Enabled = enabled == true
	player:SetAttribute("RadarHudOpen", enabled == true)
	if enabled == true then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
	setRadarLoop(tower, enabled == true)
	setRadarInventoryHidden(enabled == true)
	pulseElapsed = PULSE_INTERVAL
	refreshElapsed = REFRESH_INTERVAL - 0.5
	warn("[RadarTowerHud]", enabled == true and "opened" or "closed")
end)

snapshotEvent.OnClientEvent:Connect(function(records)
	latestServerSnapshot = typeof(records) == "table" and records or nil
	if gui.Enabled then refreshRadarContacts() end
end)

player.CharacterAdded:Connect(function()
	gui.Enabled = false
	player:SetAttribute("RadarHudOpen", false)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	setRadarLoop(nil, false)
	setRadarInventoryHidden(false)
end)

-- McDonaldsJukeboxClient

-- Local presentation only. The server jukebox chooses and plays songs; this
-- script reflects its JukeboxTrack attribute on the physical button.

local emitter = workspace:FindFirstChild("McDonaldsMusicEmitter") or workspace:WaitForChild("McDonaldsJukebox")
if not emitter:IsA("BasePart") then
	warn("McDonalds jukebox emitter must be a BasePart for the display")
	return
end

local ACTIVE_COLOR = Color3.fromRGB(255, 0, 0)
local SILENT_COLOR = Color3.fromRGB(120, 120, 120)
local TITLE_DURATION = 5

local titleGui = Instance.new("BillboardGui")
titleGui.Name = "McDonaldsJukeboxTitle"
titleGui.Adornee = emitter
titleGui.AlwaysOnTop = true
titleGui.LightInfluence = 0
titleGui.Size = UDim2.fromOffset(260, 36)
titleGui.StudsOffset = Vector3.new(0, 1.8, 0)
titleGui.Enabled = false
titleGui.Parent = emitter

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.fromScale(1, 1)
title.Font = Enum.Font.GothamBold
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 16
title.TextStrokeTransparency = 0.35
title.TextWrapped = true
title.Parent = titleGui

local titleToken = 0

local function updateDisplay()
	local trackName = emitter:GetAttribute("JukeboxTrack")
	local isSilent = trackName == nil or trackName == "Silence"

	emitter.Color = isSilent and SILENT_COLOR or ACTIVE_COLOR
	emitter.Material = isSilent and Enum.Material.Plastic or Enum.Material.Neon

	titleToken += 1
	local token = titleToken
	if isSilent then
		titleGui.Enabled = false
		return
	end

	title.Text = tostring(trackName)
	titleGui.Enabled = true
	task.delay(TITLE_DURATION, function()
		if titleToken == token then
			titleGui.Enabled = false
		end
	end)
end

emitter:GetAttributeChangedSignal("JukeboxTrack"):Connect(updateDisplay)
updateDisplay()

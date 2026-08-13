-- Light Saber SlashFlash LocalScript (backup-13 behavior).
-- Place this inside the active Light Saber Tool as a LocalScript named SlashFlash.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local tool = script.Parent
local FLASH_COLOR = Color3.fromRGB(120, 220, 255)

local function isEquipped()
	local parent = tool.Parent
	return parent and parent:IsA("Model") and parent:FindFirstChildOfClass("Humanoid") ~= nil
end

local function findBlade()
	for _, child in tool:GetChildren() do
		if child:IsA("BasePart") and child.Material == Enum.Material.Neon and child.Size.X > 1 then
			return child
		end
	end
	return nil
end

local function slashFlash()
	local blade = findBlade()
	if not blade then return end

	local flash = Instance.new("Part")
	flash.Name = "SlashFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.5, 0.5, 0.5)
	flash.Material = Enum.Material.Neon
	flash.Transparency = 1
	flash.Color = FLASH_COLOR
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false

	local light = Instance.new("PointLight")
	light.Color = FLASH_COLOR
	light.Brightness = 2
	light.Range = 12
	light.Parent = flash

	flash.CFrame = blade.CFrame * CFrame.new(blade.Size.X / 2, 0, 0)
	flash.Parent = workspace
	task.delay(0.06, function()
		flash:Destroy()
	end)
end

player:GetMouse().Button1Down:Connect(function()
	if isEquipped() then
		slashFlash()
	end
end)

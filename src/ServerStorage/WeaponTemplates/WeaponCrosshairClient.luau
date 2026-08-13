local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local tool = script.Parent

local hud
local followMouse

local function isCenteredAim()
	return player:GetAttribute("WeaponShoulderAim") == true
		or player:GetAttribute("WeaponFirstPerson") == true
end

tool.Equipped:Connect(function(mouse)
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("WeaponHud")
	if existing then
		existing:Destroy()
	end

	hud = tool:WaitForChild("WeaponHud"):Clone()
	hud.Name = "WeaponHud"
	hud.Parent = playerGui

	local ammoHud = hud:FindFirstChild("AmmoHud")
	if ammoHud then
		ammoHud.Visible = false
	end

	UserInputService.MouseIconEnabled = false
	followMouse = RunService.RenderStepped:Connect(function()
		local crosshair = hud and hud:FindFirstChild("Crosshair")
		if not crosshair then return end

		if isCenteredAim() then
			crosshair.Position = UDim2.fromScale(0.5, 0.5)
		else
			crosshair.Position = UDim2.fromOffset(mouse.X, mouse.Y)
		end
	end)
end)

tool.Unequipped:Connect(function()
	if followMouse then
		followMouse:Disconnect()
		followMouse = nil
	end

	UserInputService.MouseIconEnabled = true
	if hud then
		hud:Destroy()
		hud = nil
	end
end)

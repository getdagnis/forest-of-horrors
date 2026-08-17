-- [disabled] bullet -- deliberately currently unused
--
-- Retained only as an archival visual-effect template for the imported model.
-- MountedTurretController no longer clones or enables it: client-created
-- projectiles cannot be authoritative damage, and its old Touched handler
-- could break arbitrary unanchored map parts.  TurretCombatSystem now handles
-- validated server damage; the controller draws a short harmless local tracer.

function hit(hit)
	if hit.Name == "debrispart" then return end
	local ray = Ray.new(script.Value.Value.Position, (script.Parent.Position - script.Value.Value.Position).unit * 500)
	local parto, positiono = workspace:FindPartOnRay(ray,script.Parent, false, true)
	
	local part = hit
	if part.Anchored == false then
		part:BreakJoints()
		local a = part.Position
		local b = script.Value.Value.Position
		local dir = (a - b).unit

		part.Velocity = part.Velocity + dir * math.random(10,20) + Vector3.new(math.random(-10,10),math.random(-10,10),math.random(-10,10))
------- extreme math equations
		local v = 30
		local c = 50
		local m = part:GetMass()
		if m< 20 then
			m = 20
		end
		part.RotVelocity =Vector3.new(math.random(-v,v)/(m/c),math.random(-v,v)/(m/c),math.random(-v,v)/(m/c))
		game:GetService("Debris"):AddItem(script.Parent,0.1)--penetration
	
	end
	local a = part.Parent:findFirstChild("Humanoid")
	local b = part.Parent.Parent:findFirstChild("Humanoid")
		local debrispart = Instance.new("Part")
		debrispart.Name="debrispart"
		debrispart.Size = Vector3.new(0.05,0.05,0.05)
		debrispart.BrickColor = part.BrickColor
		debrispart.Anchored=true
		debrispart.CanCollide = false
		debrispart.Transparency=1
		debrispart.Position=positiono
		debrispart.Parent=game.Workspace
		if a == nil and b == nil then
		local thingy = script.debris:Clone()
		thingy.Color=ColorSequence.new(part.Color,part.Color)
		thingy.Parent=debrispart
		spawn(function()
		thingy:Emit(10)
		end)
		end
		if a ~= nil or b ~= nil then
		local thingy = script.blood:Clone()
		thingy.Parent=debrispart
		spawn(function()
		thingy:Emit(10)
		end)
		end
		game:GetService("Debris"):AddItem(debrispart,1)
		game:GetService("Debris"):AddItem(script.Parent,0.05)
		
	--[[if position ~= nil then
	end]]--
	
end

	script.Parent.Touched:connect(hit)

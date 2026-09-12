-- TurretCombatSystem > ServerScriptService 
-- Server authority for legacy mounted machine guns. The original tower
-- LocalScript remains responsible only for turning, recoil, sound, smoke, and
-- yellow tracer presentation; this Script validates every damaging hit/score.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("TurretCombatConfig"))
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local MonsterHitFeedback = require(ReplicatedStorage:WaitForChild("MonsterHitFeedback"))

local function getOrCreateRemoteEvent(name)
	local event = ReplicatedStorage:FindFirstChild(name)
	if event and event:IsA("RemoteEvent") then return event end
	event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = ReplicatedStorage
	return event
end

local shotEvent = getOrCreateRemoteEvent("TurretShot")
local damageLabelEvent = getOrCreateRemoteEvent("MonsterDamageLabel")
local lastShotAt = {}
local barrelRound = {}
local lastReceiptLogAt = {}
local lastDiagnosticLogAt = {}

local function isPlayerInActiveRound(player)
	return player and workspace:GetAttribute("RoundState") == "Active"
		and player:GetAttribute("EscapedNightmare") ~= true
end

local function isCurrentGeneration(generation)
	return typeof(generation) == "number" and generation == workspace:GetAttribute("RoundGeneration")
end

warn("[TurretCombat] server started; RemoteEvent ready:", shotEvent:GetFullName())

local function setStatus(turret, status, detail)
	-- These attributes are deliberately short-lived diagnostic evidence in
	-- Studio: selecting the marked gun Model after a test shows whether a shot
	-- arrived, was rejected, missed, or hit a monster without Output spam.
	turret:SetAttribute("TurretCombatStatus", status)
	turret:SetAttribute("TurretCombatLastShotAt", workspace:GetServerTimeNow())
	if detail then turret:SetAttribute("TurretCombatDetail", detail) end
end

local function logDiagnostic(player, turret, status, detail)
	local now = os.clock()
	if now - (lastDiagnosticLogAt[player] or 0) < 1 then return end
	lastDiagnosticLogAt[player] = now
	warn("[TurretCombat]", player.Name, status, "at", turret:GetFullName(), detail or "")
end

local function getMonsterModelFromHit(instance)
	local current = instance
	while current do
		if current:IsA("Model") and MonsterManager.getConfig(current) then return current end
		current = current.Parent
	end
	return nil
end

local function getBarrel(turret)
	local first = turret:FindFirstChild("gunpart", true)
	local second = turret:FindFirstChild("gunpart2", true)
	if not (first and first:IsA("BasePart")) then first = nil end
	if not (second and second:IsA("BasePart")) then second = nil end
	if not first then return second end
	if not second then return first end
	barrelRound[turret] = (barrelRound[turret] or 0) + 1
	return barrelRound[turret] % 2 == 1 and first or second
end

local function canFire(player, turret)
	local now = os.clock()
	-- GetDebugId is Plugin-only and crashes a normal server Script. Instance
	-- values are valid Luau table keys, so retain the per-player/per-turret
	-- fire limit directly without using any privileged API.
	local playerShots = lastShotAt[player]
	if not playerShots then
		playerShots = {}
		lastShotAt[player] = playerShots
	end
	if playerShots[turret] and now - playerShots[turret] < Config.FireInterval then return false end
	playerShots[turret] = now
	return true
end

local function raycastParams(player, turret)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, turret }
	params.IgnoreWater = true
	return params
end

local function monsterAtAimPoint(aimPoint)
	-- This legacy tower supplies a client-side aim point but never gives the
	-- server a reliable mounted-player or barrel relationship. Be deliberately
	-- forgiving: if the barrel ray misses, damage the living monster the player
	-- was actually pointing at within this small radius.
	local closestMonster
	local closestDistance = math.huge
	for _, part in workspace:GetPartBoundsInRadius(aimPoint, Config.AimAssistRadius) do
		local monster = getMonsterModelFromHit(part)
		if monster then
			local distance = (part.Position - aimPoint).Magnitude
			if distance < closestDistance then
				closestMonster = monster
				closestDistance = distance
			end
		end
	end
	return closestMonster
end

local function hitMonster(player, model)
	local humanoid = MonsterManager.getMonsterHumanoid(model)
	if not humanoid or humanoid.Health <= 0 then return end
	if model.Name == "BombMonster" and model:GetAttribute("BombWarningActive") == true then return end
	local damage = MonsterManager.getPlayerWeaponDamage(model, Config.Damage)
	if damage <= 0 then return end

	local willDie = humanoid.Health <= damage
	MonsterManager.recordPlayerDamage(humanoid, player, damage, Config.ShotColor)
	-- BombMonster is an ignitable, reusable world target. Keep the legacy
	-- permanent-kill behaviour only for the separate old "Monster" model.
	if willDie and model.Name == "Monster" then
		MonsterManager.markPermanentKill(humanoid, "Turret")
	end
	humanoid:TakeDamage(damage)

	if humanoid.Health > 0 then
		damageLabelEvent:FireClient(player, model, humanoid.Health, humanoid.MaxHealth, workspace:GetAttribute("RoundGeneration"))
	end
	MonsterHitFeedback.flash(model, Config.ShotColor, Config.FlashSeconds)
end

shotEvent.OnServerEvent:Connect(function(player, turret, aimPoint, generation)
	if typeof(turret) ~= "Instance" or not turret:IsA("Model") or turret:GetAttribute("Turret") ~= true then return end
	if not isPlayerInActiveRound(player) or not isCurrentGeneration(generation) then
		setStatus(turret, "Rejected: inactive or stale round")
		return
	end
	local now = os.clock()
	if now - (lastReceiptLogAt[player] or 0) >= 1 then
		lastReceiptLogAt[player] = now
		warn("[TurretCombat] server received shot from", player.Name, "for", turret:GetFullName())
	end
	if typeof(aimPoint) ~= "Vector3" then
		setStatus(turret, "Rejected: invalid aim point")
		logDiagnostic(player, turret, "rejected: invalid aim point")
		return
	end
	if not canFire(player, turret) then return end

	turret:SetAttribute("TurretCombatAimPoint", aimPoint)
	local barrel = getBarrel(turret)
	local result
	local monster
	if barrel then
		turret:SetAttribute("TurretCombatBarrel", barrel:GetFullName())
		local origin = barrel.Position + barrel.CFrame.LookVector * Config.MuzzleForwardOffset
		local offset = aimPoint - origin
		if offset.Magnitude >= 0.01 then
			local distance = math.min(offset.Magnitude, Config.Range)
			result = workspace:Spherecast(origin, Config.HitRadius, offset.Unit * distance, raycastParams(player, turret))
			monster = result and getMonsterModelFromHit(result.Instance) or nil
		end
	end
	monster = monster or monsterAtAimPoint(aimPoint)
	if monster then
		hitMonster(player, monster)
		local source = result and result.Instance:GetFullName() or "aim-point assist"
		setStatus(turret, "Hit: " .. monster.Name, source)
		logDiagnostic(player, turret, "hit " .. monster.Name, "via " .. source)
	elseif result then
		setStatus(turret, "Blocked by: " .. result.Instance.Name, result.Instance:GetFullName())
		logDiagnostic(player, turret, "blocked by " .. result.Instance.Name, result.Instance:GetFullName())
	else
		setStatus(turret, "Miss: no collision in range")
		logDiagnostic(player, turret, "miss: no collision in range")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastShotAt[player] = nil
end)

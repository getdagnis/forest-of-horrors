-- Studio-only regression suite. Pass the isolated controller copy prepared by
-- the Studio test runner; its helpers are copied from the current live Script.
-- Notifications/players/peacefulness are stubbed, not production remotes.
return function(api)
	local results, fixtures = {}, {}
	local now = os.clock()
	local generation = workspace:GetAttribute("RoundGeneration")
	local function check(name, passed)
		table.insert(results, { name = name, passed = passed == true })
	end
	local function actor()
		local model = Instance.new("Model")
		model.Name = "GuardianConversationFixture"
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Anchored = true
		root.CanCollide = false
		root.Position = Vector3.new(18000, 1000, 18000)
		root.Parent = model
		local hum = Instance.new("Humanoid")
		hum.RequiresNeck = false
		hum.Parent = model
		model.Parent = workspace
		table.insert(fixtures, model)
		return model, root, hum
	end
	local function player()
		local model = actor()
		return { Character = model, Parent = game.Players, UserId = -#fixtures, Name = "TestPlayer",
			GetAttribute = function() return nil end,
			CharacterAdded = { Connect = function() return { Disconnect = function() end } end },
		}
	end
	local function state(p)
		local model, _, hum = actor()
		local s = { model = model, humanoid = hum, mode = "unbonded", trust = {}, playerHitTimes = {},
			originalPartColors = {}, lastMonsterHit = {}, lastRoarAt = -math.huge,
		}
		local r = api.getTrustRecord(s, p)
		r.lastAimAt = now
		r.aimSince = now - 10
		return s, r
	end
	local function last(name)
		local messages = api.events[name].sent
		return messages[#messages]
	end
	local ok, err = xpcall(function()
		local p = player()
		api.players.list = { p }
		local s, r = state(p)
		api.update(s, now)
		local answer = last("WMTGuardianConversation")
		check("Completed TALKING immediately answers before offer buttons", s.mode == "offering"
			and answer[2] == "answer" and answer[5] == false and answer[8] == true)
		check("Approach retains conversation identity and generation", s.offerAttemptId == r.attemptId
			and s.offerGeneration == generation and answer[6] == generation and answer[7] == r.attemptId)
		api.cancel(s, "Come closer so I can reach you.")
		local result = last("WMTRescueResult")
		check("Pre-visible offer cancellation sends its reason", result[3] == false
			and result[4] == "Come closer so I can reach you." and result[6] == r.attemptId)

		s, r = state(p)
		s.playerHitTimes[p] = { now - 2, now - 1, now }
		api.update(s, now)
		check("Third recent hit produces a temporary explicit refusal", last("WMTGuardianConversation")[4] == "you hurt me before"
			and s.mode == "unbonded" and r.blockedUntilAimBreak)

		s, r = state(p)
		api.context.peaceful = false
		r.aimSince = now - 3.1 -- 0.1 visible seconds; still inside danger cutoff.
		r.aimSince = now - 7.9 -- Three silent seconds plus 4.9 visible seconds.
		api.update(s, now)
		check("Nearby danger produces explicit response", last("WMTGuardianConversation")[4] == "they are still near"
			and not r.talking)
		api.context.peaceful = true

		s, r = state(p)
		api.context.peaceful = false
		r.aimSince = now - 8 -- Exactly five visible seconds: danger no longer cancels.
		api.update(s, now)
		check("Danger cutoff retains TALKING at five visible seconds", r.talking
			and not r.blockedUntilAimBreak and s.mode == "unbonded")
		r.aimSince = now - 9 -- Six visible seconds.
		api.update(s, now)
		check("Late nearby danger does not cancel almost-complete TALKING", r.talking
			and not r.blockedUntilAimBreak and s.mode == "unbonded")
		r.aimSince = now - 10
		api.update(s, now)
		check("Completed TALKING offers a pet despite newly nearby monsters", s.mode == "offering"
			and s.offerPlayer == p)
		api.context.peaceful = true

		s, r = state(p)
		r.talking = true; r.attemptId = 500; r.generation = generation; r.lastAimAt = now - 2
		api.update(s, now)
		check("Lost aim explains interrupted conversation", last("WMTGuardianConversation")[4]
			== "this was not finished" and not r.talking)

		s, r = state(p)
		api.update(s, now)
		api.wound(s, p)
		api.wound(s, p)
		check("Two incidental hits retain the approach and offer", s.mode == "offering" and s.offerPlayer == p
			and #s.playerHitTimes[p] == 2 and s.trust[p] == r)
		api.wound(s, p)
		check("Third hit during approach explains cancellation", last("WMTRescueResult")[4] == "you hurt it before"
			and s.mode == "unbonded")

		s, r = state(p)
		s.playerHitTimes[p] = { now - 62, now - 61, now - 60 }
		api.update(s, now)
		check("Old hits expire without a permanent grievance", s.mode == "offering" and s.playerHitTimes[p] == nil)
		s, r = state(p)
		r.blockedUntilAimBreak = true; r.aggressionBlocked = true
		s.playerHitTimes[p] = { now - 62, now - 61, now - 60 }
		api.update(s, now)
		check("Holding aim can recover after the aggression window expires", not r.blockedUntilAimBreak
			and not r.aggressionBlocked and s.playerHitTimes[p] == nil)

		local other = player()
		api.players.list = { p, other }
		s, r = state(p)
		local otherRecord = api.getTrustRecord(s, other)
		otherRecord.talking = true; otherRecord.attemptId = 501; otherRecord.generation = generation
		otherRecord.aimSince = now - 6; otherRecord.lastAimAt = now
		api.update(s, now)
		check("Simultaneous second conversation is not silently dropped", last("WMTGuardianConversation")[4]
			== "no" and not otherRecord.talking)
		api.players.list = { p }

		s, r = state(p)
		api.update(s, now)
		s.offerReady = true
		api.events.WMTRescueResponse:request(p, s.model, true, generation - 1, r.attemptId)
		check("Old-generation acceptance is ignored", s.mode == "offering")
		api.events.WMTRescueResponse:request(p, s.model, true, generation, r.attemptId + 1)
		check("Wrong-attempt acceptance is ignored", s.mode == "offering")
		api.context.peaceful = false
		api.events.WMTRescueResponse:request(p, s.model, true, generation, r.attemptId)
		result = last("WMTRescueResult")
		check("Matching acceptance confirms default Follow", s.mode == "pet" and s.petBehavior == "Follow"
			and result[3] == true and s.model:GetAttribute("WMTGuardianBehavior") == "Follow")
		check("Nearby monsters cannot reject an already visible offer", result[3] == true)
		api.context.peaceful = true
		s.model.HumanoidRootPart.Anchored = true
		api.guardians[s.model] = s
		api.events.WMTGuardianPetCommand:request(other, s.model, "Hunt", generation, 1)
		check("Other player cannot command the pet", last("WMTGuardianPetCommandResult")[3] == false
			and s.petBehavior == "Follow")
		api.events.WMTGuardianPetCommand:request(p, s.model, "Open", generation, 2)
		check("Owner can open the command menu nearby", last("WMTGuardianPetCommandResult")[3] == true)
		task.wait(0.16)
		api.events.WMTGuardianPetCommand:request(p, s.model, "Hunt", generation, 3)
		check("Owner Hunt command is acknowledged and replicated", last("WMTGuardianPetCommandResult")[3] == true
			and s.petBehavior == "Hunt" and s.model:GetAttribute("WMTGuardianBehavior") == "Hunt")
		p.Character.HumanoidRootPart.Position += Vector3.new(7, 0, 0)
		task.wait(0.16)
		api.events.WMTGuardianPetCommand:request(p, s.model, "Follow", generation, 4)
		check("Out-of-range command explains rejection", last("WMTGuardianPetCommandResult")[4]
			== "it must be closer" and s.petBehavior == "Hunt")
	end, debug.traceback)
	for _, fixture in ipairs(fixtures) do fixture:Destroy() end
	if not ok then table.insert(results, { name = "Conversation harness completed", passed = false, details = err }) end
	return results
end

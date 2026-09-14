-- Run in the Studio Edit command bar / Studio MCP, never as a game Script.
-- Also load GuardianConversation.studio.luau and GuardianHunt.studio.luau into
-- temporary ModuleScripts named __GuardianConversationRegression and
-- __GuardianHuntRegression under ServerScriptService.
-- In Play/server: require(s.__GuardianConversationRegression)(require(s.__GuardianConversationControllerTest))
-- and require(s.__GuardianHuntRegression)(), where s = game.ServerScriptService.
-- After Play, remove all three temporary Modules. No production hooks ship.
assert(game:GetService("RunService"):IsStudio() and not game:GetService("RunService"):IsRunning(), "Studio Edit only")
local ss = game:GetService("ServerScriptService")
assert(not ss:FindFirstChild("__GuardianConversationControllerTest"), "Remove previous test copy first")
local source = [[local testContext = {peaceful=true}
local testEvents = {}
local testPlayers = {list={}}
function testPlayers:GetPlayers() return self.list end
function testPlayers:GetPlayerByUserId() return nil end
]] .. ss.GuardianMonsterSystem.Source
source = source:gsub('local Players = game:GetService%("Players"%)', 'local Players = testPlayers', 1)
local first = assert(source:find("local function getOrCreateRemoteEvent(name)", 1, true))
local last = assert(source:find("\nlocal rescueEvent", first, true))
source = source:sub(1, first - 1) .. [[local function getOrCreateRemoteEvent(name)
 local event={sent={},connections={}}
 event.OnServerEvent={Connect=function(_,callback)
  local c={Connected=true,callback=callback}
  function c:Disconnect() self.Connected=false end
  table.insert(event.connections,c) return c
 end}
 function event:FireClient(player,...) table.insert(self.sent,table.pack(player,...)) end
 function event:request(player,...)
  for _,c in ipairs(self.connections)do if c.Connected then c.callback(player,...) end end
 end
 testEvents[name]=event return event
end
]] .. source:sub(last)
local original = "local radarRange = getOfferRadarRange(playerRoot.Position)\n\treturn not hasHostileMonsterNearby(playerRoot.Position, radarRange, guardian)"
first = assert(source:find(original, 1, true), "Peacefulness helper changed: update harness deliberately")
source = source:sub(1, first - 1) .. "return testContext.peaceful" .. source:sub(first + #original)
first = assert(source:find('Workspace:GetAttributeChangedSignal("RoundState"):Connect(stopRoundActivity)', 1, true))
last = assert(source:find("local function updateGuardian(state)", first, true))
source = source:sub(1, first - 1) .. source:sub(last)
first = assert(source:find('\nfor _, item in Workspace:GetDescendants() do\n\tif item:IsA("Model") then\n\t\tsetupGuardian(item)', 1, true))
source = source:sub(1, first - 1) .. [[
return {getTrustRecord=getTrustRecord,update=updateTrustRitual,present=presentOffer,
cancel=cancelOffer,wound=resetTrustAfterPlayerHit,events=testEvents,players=testPlayers,
context=testContext,guardians=guardians}
]]
local copy = Instance.new("ModuleScript")
copy.Name = "__GuardianConversationControllerTest"
copy.Source = source
copy.Parent = ss
print("Isolated guardian helper copy prepared. Start Play to run the suites.")

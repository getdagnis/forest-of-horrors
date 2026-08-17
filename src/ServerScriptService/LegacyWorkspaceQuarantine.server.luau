-- LegacyWorkspaceQuarantine: one-pass, reversible shutdown for discarded
-- marketplace content. This script intentionally scopes itself to exactly the
-- two folders below; it never searches or changes any other Workspace area.
--
-- Studio placement: ServerScriptService.LegacyWorkspaceQuarantine (Script).
-- Re-enable an individual BaseScript manually in Studio if a quarantined model
-- is later restored. ModuleScripts have no Disabled property in Roblox: they
-- cannot run by themselves, so they are marked and reported while every
-- executable Script/LocalScript in these roots is disabled.

local Workspace = game:GetService("Workspace")

local ROOT_NAMES = {
	"Environment",
	"OldUnderground",
}

local function quarantineRoot(rootName)
	local root = Workspace:FindFirstChild(rootName)
	if not root then
		warn("[LegacyWorkspaceQuarantine] missing root; skipped:", "Workspace." .. rootName)
		return 0, 0
	end

	local disabledCount = 0
	local moduleCount = 0
	for _, instance in ipairs(root:GetDescendants()) do
		if instance:IsA("BaseScript") then
			instance.Disabled = true
			instance:SetAttribute("LegacyWorkspaceQuarantined", true)
			disabledCount += 1
			warn("[LegacyWorkspaceQuarantine] disabled", instance.ClassName, instance:GetFullName())
		elseif instance:IsA("ModuleScript") then
			-- ModuleScripts have no Disabled property and do not start on their own.
			-- The attribute records the quarantine without moving or deleting it.
			instance:SetAttribute("LegacyWorkspaceQuarantined", true)
			moduleCount += 1
			warn("[LegacyWorkspaceQuarantine] marked inert ModuleScript", instance:GetFullName())
		end
	end

	return disabledCount, moduleCount
end

local totalDisabled = 0
local totalModules = 0
for _, rootName in ipairs(ROOT_NAMES) do
	local disabledCount, moduleCount = quarantineRoot(rootName)
	totalDisabled += disabledCount
	totalModules += moduleCount
end

warn(
	"[LegacyWorkspaceQuarantine] complete; disabled",
	totalDisabled,
	"Script/LocalScript instances and marked",
	totalModules,
	"ModuleScripts. No other Workspace roots were inspected."
)

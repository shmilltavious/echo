-- R15 rig — Motor6D joints already connect every limb, so NO welds needed here.
-- Adding WeldConstraints on top of Motor6Ds over-constrains the rig and causes
-- it to fall over or slide sideways.
local foundMonster = workspace:FindFirstChild("Monster") or workspace:WaitForChild("Rig", 5)
if not (foundMonster and foundMonster:IsA("Model")) then
	warn("MonsterSetup disabled: expected Workspace.Monster or Workspace.Rig model.")
	return
end

local monsterModel = foundMonster
local rootPart = monsterModel:WaitForChild("HumanoidRootPart", 5)
local humanoid = monsterModel:WaitForChild("Humanoid", 5)
if not (rootPart and rootPart:IsA("BasePart") and humanoid and humanoid:IsA("Humanoid")) then
	warn("MonsterSetup disabled: monster is missing Humanoid or HumanoidRootPart.")
	return
end

-- Server owns physics so NPC movement is smooth and authoritative
rootPart:SetNetworkOwner(nil)

humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)

-- PrimaryAxisOnly locks only the upright (Y) axis so the rig can't tip over,
-- while still allowing AutoRotate to turn it freely to face its movement direction.
-- math.huge MaxTorque causes physics instability; 2e4 is firm enough without fighting the humanoid.
local attachment = Instance.new("Attachment")
attachment.Name = "UprightAttachment"
attachment.Parent = rootPart

local alignOrientation = Instance.new("AlignOrientation")
alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
alignOrientation.Attachment0 = attachment
alignOrientation.PrimaryAxisOnly = true
alignOrientation.MaxTorque = 2e4
alignOrientation.Responsiveness = 30
alignOrientation.Parent = rootPart

print("Monster rig ready")

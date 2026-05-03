-- R15 rig — Motor6D joints already connect every limb, so NO welds needed here.
-- Adding WeldConstraints on top of Motor6Ds over-constrains the rig and causes
-- it to fall over or slide sideways.
local monsterModel = workspace:WaitForChild("Rig")
local rootPart = monsterModel:WaitForChild("HumanoidRootPart")
local humanoid = monsterModel:WaitForChild("Humanoid")

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

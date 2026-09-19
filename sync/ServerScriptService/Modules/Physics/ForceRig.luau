
--[[
	ForceRig
	========
	Camada física de baixo nível, compartilhada entre HumanoidMovement e
	NPCMovement (EntityWrapper.luau). Existe pra resolver o problema de raiz
	do sistema antigo: setar `root.AssemblyLinearVelocity` direto, uma vez por
	Heartbeat, briga com o resto da simulação de física.
]]

local ForceRig = {}
ForceRig.__index = ForceRig

local ATTACHMENT_NAME = "_ForceRigAttachment"
local LINEAR_VELOCITY_NAME = "_ForceRigVelocity"
local GRAVITY_FORCE_NAME = "_ForceRigGravityCounter"
local ORIENTATION_NAME = "_ForceRigOrientation"


function ForceRig.new(root: BasePart)
	assert(root, "[ForceRig] root não pode ser nil")

	local self = setmetatable({}, ForceRig)
	self.Root = root

	local attachment = root:FindFirstChild(ATTACHMENT_NAME) :: Attachment?
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = ATTACHMENT_NAME
		attachment.Parent = root
	end
	self.Attachment = attachment :: Attachment

	local velocity = root:FindFirstChild(LINEAR_VELOCITY_NAME) :: LinearVelocity?
	if not velocity then
		velocity = Instance.new("LinearVelocity")
		velocity.Name = LINEAR_VELOCITY_NAME
		velocity.Attachment0 = self.Attachment
		velocity.RelativeTo = Enum.ActuatorRelativeTo.World
		velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		velocity.ForceLimitsEnabled = true
		velocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		velocity.MaxAxesForce = Vector3.zero 
		velocity.VectorVelocity = Vector3.zero
		velocity.Parent = root
	end
	self.Velocity = velocity :: LinearVelocity

	local gravityForce = root:FindFirstChild(GRAVITY_FORCE_NAME) :: VectorForce?
	if not gravityForce then
		gravityForce = Instance.new("VectorForce")
		gravityForce.Name = GRAVITY_FORCE_NAME
		gravityForce.Attachment0 = self.Attachment
		gravityForce.RelativeTo = Enum.ActuatorRelativeTo.World
		gravityForce.Force = Vector3.zero
		gravityForce.Parent = root
	end
	self.GravityForce = gravityForce :: VectorForce


	self.Orientation = root:FindFirstChild(ORIENTATION_NAME) :: AlignOrientation?

	return self
end


function ForceRig:ApplyFrame(targetVelocity: Vector3, maxAxesForce: Vector3)
	self.Velocity.VectorVelocity = targetVelocity
	self.Velocity.MaxAxesForce = maxAxesForce
end


function ForceRig:Release()
	self.Velocity.MaxAxesForce = Vector3.zero
end


function ForceRig:SetAmbientGravityScale(scale: number)
	local mass = self.Root.AssemblyMass
	local gravity = workspace.Gravity
	self.GravityForce.Force = Vector3.new(0, mass * gravity * (1 - scale), 0)
end


function ForceRig:FaceDirection(direction: Vector3, responsiveness: number?)
	if direction.Magnitude < 1e-4 then
		return
	end

	if not self.Orientation then
		local orientation = Instance.new("AlignOrientation")
		orientation.Name = ORIENTATION_NAME
		orientation.Attachment0 = self.Attachment
		orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
		orientation.RigidityEnabled = false
		orientation.MaxTorque = math.huge
		orientation.MaxAngularVelocity = math.huge
		orientation.Parent = self.Root
		self.Orientation = orientation
	end

	local rig = self.Orientation :: AlignOrientation
	rig.MaxTorque = math.huge
	rig.Responsiveness = responsiveness or 25

	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		flat = direction
	end
	rig.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
end


function ForceRig:ReleaseFaceDirection()
	if self.Orientation then
		(self.Orientation :: AlignOrientation).MaxTorque = 0
	end
end

function ForceRig:Destroy()
	if self.Velocity then
		self.Velocity:Destroy()
	end
	if self.GravityForce then
		self.GravityForce:Destroy()
	end
	if self.Orientation then
		self.Orientation:Destroy()
	end
	if self.Attachment then
		self.Attachment:Destroy()
	end
end

return ForceRig

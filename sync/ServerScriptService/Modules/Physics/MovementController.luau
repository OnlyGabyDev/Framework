
--[[
	MovementController
	===================
	Loop físico central do movimento. Reescrito pra resolver o jitter na raiz
	(ver ForceRig.luau pra explicação técnica completa do porquê) e pra
	suportar dashes que zeram gravidade, dashes "duros" parciais (só alguns
	eixos) e dashes com direção reavaliada a cada frame (steering por câmera)
]]

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local Settings = require(script.Parent.Settings)

local MovementController = {}
local trackedEntities = {}

local AXES = { "X", "Y", "Z" }

local function axisOf(v: Vector3, axis: string): number
	if axis == "X" then
		return v.X
	elseif axis == "Y" then
		return v.Y
	else
		return v.Z
	end
end

local function tableToVector3(t: { [string]: number }): Vector3
	return Vector3.new(t.X, t.Y, t.Z)
end


local function RotateTowards(current: Vector3, target: Vector3, maxRadians: number): Vector3
	if current.Magnitude < 1e-6 then
		return target.Unit
	end

	local currentUnit = current.Unit
	local targetUnit = target.Unit

	local dot = math.clamp(currentUnit:Dot(targetUnit), -1, 1)
	local angle = math.acos(dot)

	if angle <= maxRadians or angle < 1e-4 then
		return targetUnit
	end

	local axis = currentUnit:Cross(targetUnit)
	if axis.Magnitude < 1e-6 then
		axis = currentUnit:Cross(Vector3.yAxis)
		if axis.Magnitude < 1e-6 then
			axis = Vector3.xAxis
		end
	end


	local rotation = CFrame.fromAxisAngle(axis.Unit, maxRadians)
	return (rotation * currentUnit).Unit
end

function MovementController.Register(comp)
	if comp and comp.Entity then
		trackedEntities[comp.Entity] = comp
	end
end

function MovementController.Unregister(comp)
	if comp and comp.Entity then
		trackedEntities[comp.Entity] = nil
	end
end

function MovementController.ProcessEntity(comp, dt)
	local wrapper = comp.MovementWrapper
	local entity = comp.Entity

	if not wrapper or not entity then
		return
	end

	if comp.IsFrozen then

		wrapper:SetFrozen(true)
		return
	else
		wrapper:SetFrozen(false)
	end

	local tags = { canMove = true, canDisplace = true }
	if entity:HasComponent(entity.ComponentKey.Status) then
		local activeTags = entity.GetActiveTags()
		if activeTags[StateTable.Enum.Tags.canMove] ~= nil then
			tags.canMove = activeTags[StateTable.Enum.Tags.canMove]
		end
		if activeTags[StateTable.Enum.Tags.canDisplace] ~= nil then
			tags.canDisplace = activeTags[StateTable.Enum.Tags.canDisplace]
		end
	end


	wrapper:SetSpeed(comp:GetSpeed())
	wrapper:SetJumpForce(comp:GetJumpForce())
	local gravityScale = 1
	if entity:HasComponent(entity.ComponentKey.Attributes) then
		gravityScale = entity.GetStat("GravityScale", 1)
	end
	wrapper:SetAmbientGravityScale(gravityScale)


	if comp.Direction ~= Vector3.zero then
		wrapper:Move(tags.canMove and comp.Direction or Vector3.zero)
	end


	local targetVelocity = { X = 0, Y = 0, Z = 0 }
	local maxForce = { X = 0, Y = 0, Z = 0 }
	local hardPriority = { X = -math.huge, Y = -math.huge, Z = -math.huge }
	local hardClaimed = { X = false, Y = false, Z = false }
	local softAccum = { X = 0, Y = 0, Z = 0 }
	local hasAnyForce = false
	local faceRequest: Vector3? = nil
	local faceResponsiveness: number? = nil

	if tags.canDisplace then
		for forceId, forceEntry in pairs(comp.ActiveForces) do
			local data = forceEntry.Data
			local hard = data.Hard == true


			if not tags.canMove and not hard and data.RequiresControl ~= false then
				comp:RemoveForce(forceId)
				continue
			end

			forceEntry.ElapsedTime += dt
			local duration = data.Duration or 0.5
			if forceEntry.ElapsedTime >= duration then
				comp:RemoveForce(forceId)
				continue
			end

			hasAnyForce = true

			local elapsed = forceEntry.ElapsedTime
			local speed = data.Speed
			if type(speed) == "function" then
				speed = speed(elapsed, duration)
			end
			speed = speed or 0

			local rawDirection = data.Direction
			if type(rawDirection) == "function" then
				rawDirection = rawDirection(elapsed, duration, {
					Entity = entity,
					MovementComponent = comp,
				})
			end
			rawDirection = (rawDirection :: Vector3?) or Vector3.zero

			local direction = rawDirection
			if data.TurnRate and rawDirection.Magnitude > 1e-4 then
				forceEntry.CurrentDirection = forceEntry.CurrentDirection or rawDirection.Unit
				direction = RotateTowards(forceEntry.CurrentDirection, rawDirection, data.TurnRate * dt)
				forceEntry.CurrentDirection = direction
			elseif rawDirection.Magnitude > 1e-4 then
				forceEntry.CurrentDirection = rawDirection.Unit
			end

			local velocity = direction * speed

			local axes = data.Axes
			if not axes then
				axes = hard and { X = true, Y = true, Z = true } or { X = true, Y = false, Z = true }
			end
			if data.IgnoreGravity then
				axes = { X = axes.X, Y = true, Z = axes.Z }
			end

			local priority = data.Priority or 0
			local budget = data.MaxForce or (hard and Settings.Hard_Force_Strength or Settings.Soft_Force_Strength)

			for _, axis in AXES do
				if axes[axis] then
					if hard then
						if priority >= hardPriority[axis] then
							hardPriority[axis] = priority
							hardClaimed[axis] = true
							targetVelocity[axis] = axisOf(velocity, axis)
							maxForce[axis] = budget
						end
					elseif not hardClaimed[axis] then
						softAccum[axis] += axisOf(velocity, axis)
					end
				end
			end

			local wantsFace = data.FaceDirection
			if wantsFace == nil then
				wantsFace = hard
			end
			if wantsFace and direction.Magnitude > 1e-4 then
				faceRequest = direction
				faceResponsiveness = data.Responsiveness or Settings.Face_Direction_Responsiveness
			end
		end
	else
		for forceId, forceEntry in pairs(comp.ActiveForces) do
			if not forceEntry.Data.Unstoppable then
				comp:RemoveForce(forceId)
			end
		end
	end

	for _, axis in AXES do
		if not hardClaimed[axis] and softAccum[axis] ~= 0 then
			targetVelocity[axis] = softAccum[axis]
			maxForce[axis] = Settings.Soft_Force_Strength
			hasAnyForce = true
		end
	end

	if hasAnyForce then
		wrapper:ApplyForceFrame(tableToVector3(targetVelocity), tableToVector3(maxForce))
	else
		wrapper:ReleaseForces()
	end

	if faceRequest then
		wrapper:FaceDirection(faceRequest, faceResponsiveness)
	else
		wrapper:ReleaseFaceDirection()
	end
end

RunService.PreSimulation:Connect(function(dt)
	for _, comp in pairs(trackedEntities) do
		local ok, err = pcall(MovementController.ProcessEntity, comp, dt)
		if not ok then
			warn("[MovementController] Erro processando entidade:", err)
		end
	end
end)

return MovementController

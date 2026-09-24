
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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utils = require(ReplicatedStorage.Utils)

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

	if comp.IsFrozen ~= comp._appliedFrozen then
		comp._appliedFrozen = comp.IsFrozen
		wrapper:SetFrozen(comp.IsFrozen)
	end
	if comp.IsFrozen then return end

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

	local canMove = tags.canMove
	wrapper:SetSpeed(canMove and comp:GetSpeed() or 0)
	wrapper:SetJumpForce(canMove and comp:GetJumpForce() or 0)
	
	local gravityScale = 1
	if entity:HasComponent(entity.ComponentKey.Attributes) then
		gravityScale = entity.GetStat(StateTable.Enum.Stats.GravityScale, 1)
	end
	wrapper:SetAmbientGravityScale(gravityScale)

	if wrapper.DrivesInput then
		wrapper:Move(canMove and comp.Direction or Vector3.zero)
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
		-- Ordem determinística por criação (ID = "F_<contador>"): empate de Priority
		-- entre duas Forces Hard sempre resolve pra mais recente, nunca pela ordem
		-- arbitrária do pairs().
		local orderedForceIds = {}
		for forceId in pairs(comp.ActiveForces) do
			table.insert(orderedForceIds, forceId)
		end
		table.sort(orderedForceIds, function(a, b)
			return (tonumber(a:match("_(%d+)$")) or 0) < (tonumber(b:match("_(%d+)$")) or 0)
		end)

		for _, forceId in orderedForceIds do
			local forceEntry = comp.ActiveForces[forceId]
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
			local velocity: Vector3
			local direction: Vector3

			if data.FollowTarget then
				-- Modo TETHER: em vez de "ande nessa direção nessa
				-- velocidade", persegue uma posição-alvo (outra entidade +
				-- offset) com um controlador proporcional. Direction como
				-- função sozinha NÃO consegue isso: sempre normaliza e usa
				-- Speed constante, então vira "atrair", não "grudar" — sem
				-- isso, arrastar um alvo diverge com o tempo porque as duas
				-- entidades resolvem força de forma independente.
				local followPart = data.FollowTarget
				if type(followPart) == "function" then
					followPart = followPart()
				end

				if followPart then
					local anchor = (followPart :: BasePart)
					local desiredPosition = data.FollowOffsetIsLocal
						and anchor.CFrame:PointToWorldSpace(data.FollowOffset or Vector3.zero)
						or (anchor.Position + (data.FollowOffset or Vector3.zero))

					local ownRoot = entity.GetRoot and entity.GetRoot()
					local currentPosition = ownRoot and ownRoot.Position or desiredPosition
					local toDesired = desiredPosition - currentPosition

					velocity = toDesired * (data.FollowResponsiveness or 10)

					if data.FollowMaxSpeed and velocity.Magnitude > data.FollowMaxSpeed then
						velocity = velocity.Unit * data.FollowMaxSpeed
					end

					direction = toDesired.Magnitude > 1e-4 and toDesired.Unit or (forceEntry.CurrentDirection or Vector3.new(0, 0, -1))
					forceEntry.CurrentDirection = direction
				else
					-- Alvo sumiu (morreu/destruído): zera velocidade até a Force expirar pelo Duration
					velocity = Vector3.zero
					direction = forceEntry.CurrentDirection or Vector3.new(0, 0, -1)
				end
			else
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
				if rawDirection.Magnitude > 1e-4 then
					rawDirection = rawDirection.Unit
				end

				direction = rawDirection
				if data.TurnRate and rawDirection.Magnitude > 1e-4 then
					forceEntry.CurrentDirection = forceEntry.CurrentDirection or rawDirection.Unit
					direction = Utils.rotateTowards(forceEntry.CurrentDirection, rawDirection, data.TurnRate * dt)
					forceEntry.CurrentDirection = direction
				elseif rawDirection.Magnitude > 1e-4 then
					forceEntry.CurrentDirection = rawDirection.Unit
				end

				velocity = direction * speed
			end

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

--!strict
--!native
--!optimize 2

-- HitboxBehaviors: comportamentos pós-nascimento reutilizáveis. Nenhuma
-- função aqui CRIA hitbox — recebe um hitbox/carrier já spawnado (ver
-- HitboxSpawner) e devolve um callback pronto pra hitbox:OnUpdate(callback).
-- Composição, não caso especial: um preset combina 1+ desses.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utils = require(ReplicatedStorage.Utils)
local HitboxSpawner = require(script.Parent.HitboxSpawner)

local Behaviors = {}

--[[ Aumenta o Radius (Spherecast) uniformemente em todas as direções. ]]
function Behaviors.ExpandUniform(hitbox: any, ratePerSecond: number, maxRadius: number?)
	return function(dt: number)
		local newRadius = hitbox.CastData.Radius + ratePerSecond * dt
		if maxRadius then
			newRadius = math.min(newRadius, maxRadius)
		end
		hitbox.CastData.Radius = newRadius
	end
end

--[[ Aumenta o Size (Blockcast) só no eixo local pedido ("X"|"Y"|"Z"). ]]
function Behaviors.ExpandDirectional(hitbox: any, axis: string, ratePerSecond: number, maxSize: number?)
	assert(axis == "X" or axis == "Y" or axis == "Z", "[HitboxBehaviors] axis precisa ser 'X', 'Y' ou 'Z'")
	return function(dt: number)
		local size = hitbox.CastData.Size
		local growth = ratePerSecond * dt
		local current = (size :: any)[axis]
		local target = maxSize and math.min(current + growth, maxSize) or (current + growth)

		if axis == "X" then
			hitbox.CastData.Size = Vector3.new(target, size.Y, size.Z)
		elseif axis == "Y" then
			hitbox.CastData.Size = Vector3.new(size.X, target, size.Z)
		else
			hitbox.CastData.Size = Vector3.new(size.X, size.Y, target)
		end
	end
end

--[[
Move o carrier em linha reta. Direction/Speed aceitam valor FIXO ou função
(elapsed, duration) -> valor — MESMO PADRÃO de MovementComponent:AddForce.
Não reinvente essa convenção, reuse-a (consistência cognitiva pra quem ler depois).
]]
function Behaviors.LinearMove(carrier: Instance, direction: any, speed: any, duration: number)
	local elapsed = 0
	return function(dt: number)
		elapsed += dt

		local dir = direction
		if type(dir) == "function" then
			dir = dir(elapsed, duration)
		end
		if dir.Magnitude > 1e-4 then
			dir = dir.Unit
		end

		local spd = speed
		if type(spd) == "function" then
			spd = spd(elapsed, duration)
		end

		local currentPosition = (carrier :: BasePart).Position
		local newPosition = currentPosition + dir * spd * dt
		HitboxSpawner.SetCarrierCFrame(carrier, CFrame.lookAt(newPosition, newPosition + dir))
	end
end

--[[
Homing: mesmo contrato de LinearMove, mas Direction é recalculada a cada frame
mirando `getTarget()`. Se getTarget() devolver nil (alvo morreu/saiu), mantém
a última direção conhecida — não trava, não erra.
@param getTarget () -> BasePart? - ex: function() return targetEntity.GetRoot() end
@param turnRateRadPerSec number? - se omitido, homing perfeito (vira instantâneo)
]]
function Behaviors.Homing(carrier: Instance, getTarget: () -> BasePart?, speed: any, turnRateRadPerSec: number?)
	local elapsed = 0
	local currentDirection: Vector3? = nil

	return function(dt: number)
		elapsed += dt
		local carrierPart = carrier :: BasePart
		local targetPart = getTarget()

		local desiredDirection = currentDirection
		if targetPart then
			local toTarget = targetPart.Position - carrierPart.Position
			if toTarget.Magnitude > 1e-3 then
				desiredDirection = toTarget.Unit
			end
		end
		desiredDirection = desiredDirection or carrierPart.CFrame.LookVector

		if currentDirection == nil or not turnRateRadPerSec then
			currentDirection = desiredDirection
		else
			currentDirection = Utils.rotateTowards(currentDirection, desiredDirection, turnRateRadPerSec * dt)
		end

		local spd = speed
		if type(spd) == "function" then
			spd = spd(elapsed, math.huge)
		end

		local newPosition = carrierPart.Position + (currentDirection :: Vector3) * spd * dt
		HitboxSpawner.SetCarrierCFrame(carrier, CFrame.lookAt(newPosition, newPosition + (currentDirection :: Vector3)))
	end
end

return Behaviors

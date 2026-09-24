--!strict
-- HitboxPresets: combinações prontas de Spawner + Behaviors, NOMEADAS. Regra 2
-- do framework: a skill só referencia Presets.X e passa overrides pontuais —
-- nunca monta spawner+behavior na mão dentro de uma skill.

local HitboxSpawner = require(script.Parent.HitboxSpawner)
local Behaviors = require(script.Parent.HitboxBehaviors)

local Presets = {}

--[[
Anel de esferas se expandindo radialmente a partir de `center`.
@return { {hitbox: any, carrier: Instance} } - uma entrada por ponto do anel (conecte OnHit em cada uma)
]]
function Presets.ExpandingRing(casterEntity: any, center: CFrame, count: number, startRadius: number, expandRate: number, sphereRadius: number, duration: number)
	local results = {}

	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * startRadius
		local pointCFrame = center + offset

		local hitbox, carrier = HitboxSpawner.Spawn(casterEntity, pointCFrame)
		hitbox:SetCastData({ CastType = "Spherecast", Radius = sphereRadius })

		local direction = offset.Magnitude > 1e-3 and offset.Unit or Vector3.xAxis
		local move = Behaviors.LinearMove(carrier, direction, expandRate, duration)
		local grow = Behaviors.ExpandUniform(hitbox, expandRate * 0.5)

		hitbox:OnUpdate(function(dt)
			move(dt)
			grow(dt)
		end)
		hitbox:OnStopped(function()
			HitboxSpawner.Cleanup(hitbox, carrier)
		end)

		hitbox:HitStart(duration)
		table.insert(results, { hitbox = hitbox, carrier = carrier })
	end

	return results
end

--[[ Projétil teleguiado: Spherecast homing num alvo, TTL fixo. ]]
function Presets.HomingBolt(casterEntity: any, origin: CFrame, getTarget: () -> BasePart?, speed: number, radius: number, duration: number, turnRateRadPerSec: number?)
	local hitbox, carrier = HitboxSpawner.Spawn(casterEntity, origin)
	hitbox:SetCastData({ CastType = "Spherecast", Radius = radius })

	hitbox:OnUpdate(Behaviors.Homing(carrier, getTarget, speed, turnRateRadPerSec))
	hitbox:OnStopped(function()
		HitboxSpawner.Cleanup(hitbox, carrier)
	end)

	hitbox:HitStart(duration)
	return hitbox, carrier
end

--[[ Leque parado que abre em Size num eixo — ex: corte de espada. ]]
function Presets.ExpandingCone(casterEntity: any, originCFrame: CFrame, axis: string, expandRate: number, maxSize: number, duration: number)
	local hitbox, carrier = HitboxSpawner.Spawn(casterEntity, originCFrame)
	hitbox:SetCastData({ CastType = "Blockcast", Size = Vector3.new(0.1, 0.1, 0.1) })

	hitbox:OnUpdate(Behaviors.ExpandDirectional(hitbox, axis, expandRate, maxSize))
	hitbox:OnStopped(function()
		HitboxSpawner.Cleanup(hitbox, carrier)
	end)

	hitbox:HitStart(duration)
	return hitbox, carrier
end

return Presets

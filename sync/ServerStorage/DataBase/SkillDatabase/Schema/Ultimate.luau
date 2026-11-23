--[[
	UltFlight — exemplo de referência, não "a" implementação final.

	Mostra como usar os 3 campos novos de Force juntos]]--

local ServerStorage = game:GetService("ServerStorage")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local CollisionGroups = require(game:GetService("ServerScriptService").Modules.Physics.CollisionGroups)

local Skill = {

	data = {
		cooldown = 3,
		duration = 20,
		castTime = 0,
		Speed = 90,
		TurnRateDegrees = 50,  
		anim = "anim",
        traits = { StateTable.Enum.Traits.Ultimate },
	},

	callbacks = {
		onStart = function(self)
			local statsTable = self.statusTable


			self.control = statsTable.States.NoControl
			self.stateID = self.Entity.ApplyStatus(self.control, self.data.duration, self)

			self.Entity.SetActionState(statsTable.ActionStates.Self.selfCast, self)

			self:StartHitbox(self.data.duration) -- hitbox desta skill

			self.forceID = self.Entity.AddForce({
				Type = "UltFlight",
				Hard = true,
				IgnoreGravity = true,
				Priority = 20,
				Duration = self.data.duration,
				Speed = self.data.Speed,
				TurnRate = math.rad(self.data.TurnRateDegrees),
				FaceDirection = true,

				Direction = function(_elapsed, _duration, ctx)
					-- Captura LookDirection (2D, horizontal puro) travado para voo reto.
					local look = ctx.Entity.GetLookDirection()
					if look.Magnitude < 0.1 then
						return ctx.Entity.GetDirection()
					end
					return look
				end,


				-- O voo acabou: encerra a skill (a limpeza fica toda no onEnd)
				OnEnd = function()
					self:Stop(false)
				end,
			})
		end,

		onHit = function(self,result)
			local targetEntity = result.target
			self.grabbed = self.grabbed or {}
			if not targetEntity or self.grabbed[targetEntity] then return end

			-- Offset por alvo: 0, +3, -3, +6, -6... para os lados, em vez de todos no mesmo ponto
			local index = (self.grabCount or 0) + 1
			self.grabCount = index
			local side = if index % 2 == 0 then 1 else -1
			local lateral = side * math.floor(index / 2) * (self.data.GrabSpacing or 3)
			local offset = (self.data.GrabOffset or Vector3.new(0, 0, -4)) + Vector3.new(lateral, 0, 0)

			-- Agarrão rígido (AttachTo): o alvo vira parte do assembly do caster e anda com ele sem atraso,
			-- também quando o caster é um player (uma Force com FollowTarget usaria a posição atrasada dele).
			-- Dura o restante da skill: o Own abaixo solta no fim
			local release = targetEntity.AttachTo(self.Entity.GetRoot(), CFrame.new(offset))
			if not release then return end
			self.grabbed[targetEntity] = true

			-- Agarrados não colidem entre si nem com o caster; o grupo volta no fim do grab
			local restoreTarget = CollisionGroups.Assign(targetEntity.Instance, CollisionGroups.Grabbed)
			if not self.restoreCaster then
				self.restoreCaster = CollisionGroups.Assign(self.Entity.Instance, CollisionGroups.Grabber)
				self:Own(function() self.restoreCaster() end)
			end
			-- O grab pertence ao runner: cancel, morte do caster e fim do voo soltam o alvo
			self:Own(function()
				release()
				restoreTarget()
			end)
		end,

		-- Uma limpeza só, para qualquer fim (cancel, morte, duração ou fim do voo)
		onEnd = function(self)
			if self.forceID then
				self.Entity.RemoveForce(self.forceID)
				self.forceID = nil
			end
			if self.stateID then
				self.Entity.RemoveStatusByID(self.stateID)
				self.stateID = nil
			end
			self.Entity.RemoveActionState(self.Runner)
		end,
	}
}

return Skill

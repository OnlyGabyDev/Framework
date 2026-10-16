--[[
	UltFlight — exemplo de referência, não "a" implementação final.

	Mostra como usar os 3 campos novos de Force juntos]]--

local ServerStorage = game:GetService("ServerStorage")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)

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

			self.Entity.StartHitbox(self.data.duration)

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
			local grabID = targetEntity.AddForce({
				Type = "UltGrab",
				Duration = self.data.duration,
				Hard = true,
				IgnoreGravity = true,
				RequiresControl = false,
				FollowTarget = function() return self.Entity.GetRoot() end,
				FollowOffset = self.data.GrabOffset or Vector3.new(0, 0, -4),
				FollowOffsetIsLocal = true,
				FollowResponsiveness = self.data.GrabResponsiveness or 16,
				FollowMaxSpeed = self.data.Speed,
			})
			-- O grab pertence ao runner: cancel, morte do caster e fim do voo soltam o alvo
			-- (antes ele ficava preso pelos 20 s da Force, contados do hit)
			if grabID then
				self:Own(function() targetEntity.RemoveForce(grabID) end)
			end
		end,

		-- Uma limpeza só, para qualquer fim (cancel, morte, duração ou fim do voo): F54
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

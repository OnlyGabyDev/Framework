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

			self.cleanUp = function()
				if self.stateID then
					self.Entity.RemoveStatusByID(self.stateID)
					self.stateID = nil
				end
				self.Entity.RemoveActionState(self.Runner)
			end

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
					local look = ctx.Entity.GetLookDirection()
					if look.Magnitude < 0.1 then
						return ctx.Entity.GetDirection()
					end
					return look
				end,


				OnEnd = function()
					self.cleanUp()
					self:Stop(false)
				end,
			})
		end,

		onHit = function(self,result)
			local targetEntity = result.target
			targetEntity.forceID = targetEntity.AddForce({
				Type = "UltFlight",
				Hard = true,
				IgnoreGravity = true,
				Priority = 20,
				Duration = self.data.duration,
				Speed = self.data.Speed,
				TurnRate = math.rad(self.data.TurnRateDegrees),
				FaceDirection = true,

				Direction = function(_elapsed, _duration, ctx)
					local look = self.Entity.GetLookDirection()
					if look.Magnitude < 0.1 then
						return self.Entity.GetDirection()
					end
					return look
				end,


				OnEnd = function()
					if targetEntity.forceID then
						targetEntity.forceID = nil
					end
				end,
			})
		end,

		onCancel = function(self)
			if self.forceID then
				self.Entity.RemoveForce(self.forceID)
			end
			self.cleanUp()
		end,
	}
}

return Skill

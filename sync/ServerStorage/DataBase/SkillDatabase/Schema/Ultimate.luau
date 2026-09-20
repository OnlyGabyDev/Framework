--[[
	UltFlight — exemplo de referência, não "a" implementação final.

	Mostra como usar os 3 campos novos de Force juntos]]--

local Skill = {

	data = {
		cooldown = 3,
		duration = 20,
		castTime = 0,
		Speed = 90,
		TurnRateDegrees = 50,  
		anim = "anim",
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
				self.Entity.RemoveActionState()
			end

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

		onCancel = function(self)
			if self.forceID then
				self.Entity.RemoveForce(self.forceID)
			end
			self.cleanUp()
		end,
	}
}

return Skill

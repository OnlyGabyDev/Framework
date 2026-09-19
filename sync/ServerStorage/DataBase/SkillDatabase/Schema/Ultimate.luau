--[[
	UltFlight — exemplo de referência, não "a" implementação final.

	Mostra como usar os 3 campos novos de Force juntos]]--

local Skill = {

	data = {
		cooldown = 30,
		duration = 0,
		castTime = 0,
		FlightDuration = 2.5,
		Speed = 90,
		TurnRateDegrees = 180,  
		anim = "anim",
	},

	callbacks = {
		onStart = function(self)
			local statsTable = self.statusTable


			self.control = statsTable.States.NoControl
			self.stateID = self.Entity.ApplyStatus(self.control, self.data.FlightDuration + 0.5, self)

			self.Entity.SetPlayerState(statsTable.PlayerStates.Self.selfCast, self)

			self.cleanUp = function()
				if self.stateID then
					self.Entity.RemoveStatusByID(self.stateID)
					self.stateID = nil
				end
				self.Entity.RemovePlayerState()
			end

			self.forceID = self.Entity.AddForce({
				Type = "UltFlight",
				Hard = true,
				IgnoreGravity = true,
				Priority = 20,
				Duration = self.data.FlightDuration,
				Speed = self.data.Speed,
				TurnRate = math.rad(self.data.TurnRateDegrees),
				FaceDirection = true,

				Direction = function(_elapsed, _duration, ctx)
					local look = ctx.MovementComponent.LookDirection
					if look.Magnitude < 0.1 then
						return ctx.MovementComponent.Direction
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

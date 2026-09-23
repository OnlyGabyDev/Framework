local ServerStorage = game:GetService("ServerStorage")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)

local Skill = {

data = {
	duration = 0.35,
	cooldown = 0.2 + 0.35,
	castTime = 0,
	speed = 80, --150
	anim  = "anim",
},

callbacks = {
	onStart = function(self)

        --=========CLEANUP=========--
        	self.cleanUp = function()
                 if self.stateID then
                     self.Entity.RemoveStatusByID(self.stateID)
                 end
                 if self.dashForceID then
                     self.Entity.RemoveForce(self.dashForceID)
                 end
                 self.Entity.RemoveActionState(self.Runner)
			end


        self.stateID = nil
        self.dashForceID = nil

		local speed = self.data.speed
        local statsTable = self.statusTable
        local control = statsTable.States.NoControl
        local state = statsTable.ActionStates.Self.selfCast
            

        self.Entity.SetActionState(state, self)
        self.stateID = self.Entity.ApplyStatus(control, self.data.duration, self)
        

            local dir = self.Entity.GetDirection()
        if dir.Magnitude < 0.1 then
            local look = self.Entity.GetLookDirection()
            if look.Magnitude > 0.1 then
                dir = Vector3.new(look.X, 0, look.Z).Unit
            else
                dir = self.Entity.GetLastDirection()
            end
        end

        self.dashForceID = self.Entity.AddForce({
            Type = "Dash",
            Duration = self.data.duration,
            Speed = speed,
            Direction = dir,
            Hard = true,          
            IgnoreGravity = true, 
            Priority = 10,
        })
        
		self.accumulatedBleedDamage = 0
		self.isUltActive = false
		local comboOwner = "DashBleedCombo"

		-- Limpa combos residuais de Dashes anteriores para não vazar memória
		self.Entity:UnsubscribeByOwner(comboOwner)

		self.Entity:Listen({
			Role = StateTable.Enum.Roles.OUT,
			Breakpoint = StateTable.Enum.Breakpoints.onHit,
			Query = { Any = { StateTable.Enum.Traits.Melee } },
			Priority = 0,
			Owner = comboOwner,
			Limit = { Max = 1, OnExhaust = "Remove" },
			TTD = 3.5,
			Action = function(context)
				local targetEntity = context.targetEntity
				if not targetEntity then return end

				self.comboTarget = targetEntity
				self:ApplyStatus(self.statusTable.Status.Bleed, { Target = targetEntity })

				targetEntity:UnsubscribeByOwner(comboOwner)
				targetEntity:Listen({
					Role = StateTable.Enum.Roles.IN,
					Breakpoint = StateTable.Enum.Breakpoints.PostDamage,
					Priority = 0,
					Owner = comboOwner,
					TTD = 3.5,
					Action = function(tgtContext)
						if tgtContext.source and tgtContext.source.skill and tgtContext.source.skill.data and tgtContext.source.skill.data.name == "Bleed" then
							if self.isUltActive then
								self.Entity.Heal(tgtContext.damage * 3)
							else
								self.accumulatedBleedDamage += tgtContext.damage
							end
						end
					end
				})
			end
		})

		self.Entity:Listen({
			Role = StateTable.Enum.Roles.OUT,
			Breakpoint = StateTable.Enum.Breakpoints.onStart,
			Priority = 0,
			Owner = comboOwner,
			TTD = 3.5,
			Action = function(context)
				local runner = context.sourceRunner
				if runner and StateTable.HasTrait(runner.skill.data, StateTable.Enum.Traits.Ultimate) then
					self.isUltActive = true
					self.accumulatedBleedDamage = 0
				end
			end
		})

		self.Entity:Listen({
			Role = StateTable.Enum.Roles.OUT,
			Breakpoint = StateTable.Enum.Breakpoints.onEnd,
			Priority = 0,
			Owner = comboOwner,
			TTD = 3.5,
			Action = function(context)
				local runner = context.sourceRunner
				if runner and StateTable.HasTrait(runner.skill.data, StateTable.Enum.Traits.Ultimate) then
					self.isUltActive = false
					if self.comboTarget then
						self.comboTarget:UnsubscribeByOwner(comboOwner)
					end
					self.Entity:UnsubscribeByOwner(comboOwner)
				end
			end
		})

	end,    

	onEnd = function(self)
        self.cleanUp()
	end,
	
	onCancel = function(self)
        self.cleanUp()
	end,
}

}
return Skill
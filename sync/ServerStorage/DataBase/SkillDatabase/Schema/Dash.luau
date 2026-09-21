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
                 self.Entity.RemoveActionState()
                 if self.stateID then
                     self.Entity.RemoveStatusByID(self.stateID)
                 end
                 if self.dashForceID then
                     self.Entity.RemoveForce(self.dashForceID)
                 end
                 self.Entity.RemoveActionState()
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
        
        -- === PUB/SUB TEST ===
		self.accumulatedBleedDamage = 0
		self.isUltActive = false
		local comboOwner = "DashCombo_" .. tostring(tick())
		
		self.Entity:Listen({
			Role = "OUT",
			Breakpoint = StateTable.Enum.Breakpoints.onHit,
			Query = { Any = {"Melee"} }, 
			Priority = 0,
			Owner = comboOwner .. "_hit",
			Action = function(context)
				local targetEntity = context.targetEntity
				
				if not targetEntity then 
					return 
				end
				
				self.comboTarget = targetEntity
				targetEntity.ApplyStatus(self.statusTable.Status.Bleed, nil, self.Runner)
				
				targetEntity:Listen({
					Role = "IN",
					Breakpoint = StateTable.Enum.Breakpoints.OnDamage,
					Priority = 0,
					Owner = comboOwner,
					Action = function(tgtContext)
						if tgtContext.source and tgtContext.source.data and tgtContext.source.data.name == "Bleed" then
							if self.isUltActive then
								local extraHeal = tgtContext.damage * 3
                                self.Entity.Heal(extraHeal)
							else
								self.accumulatedBleedDamage += tgtContext.damage
							end
						end
					end
				})
				
				self.Entity:UnsubscribeByOwner(comboOwner .. "_hit")
			end
		})
		
		self.Entity:Listen({
			Role = "OUT",
			Breakpoint = "OnUlt",
			Priority = 0,
			Owner = comboOwner,
			Action = function(context)
				self.isUltActive = true
				self.accumulatedBleedDamage = 0
			end
		})

		self.Entity:Listen({
			Role = "OUT",
			Breakpoint = "OnUltEnd",
			Priority = 0,
			Owner = comboOwner,
			Action = function(context)
				self.isUltActive = false
				self.Entity:UnsubscribeByOwner(comboOwner)
				if self.comboTarget then
					self.comboTarget:UnsubscribeByOwner(comboOwner)
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
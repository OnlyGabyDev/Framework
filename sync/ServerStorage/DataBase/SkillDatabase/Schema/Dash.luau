
local Skill = {

data = {
	cooldown = 0.2,
	duration = 0.35,
	castTime = 0,
	speed = 80, --150
	anim  = "anim",
},

callbacks = {
	onStart = function(self)

        --=========CLEANUP=========--
        	self.cleanUp = function()
                 self.Entity.RemovePlayerState()
                 if self.stateID then
                     self.Entity.RemoveStatusByID(self.stateID)
                 end
                 if self.dashForceID then
                     self.Entity.RemoveForce(self.dashForceID)
                 end
                 self.Entity.RemovePlayerState()
			end


        self.stateID = nil
        self.dashForceID = nil

		local speed = self.data.speed
        local statsTable = self.statusTable
        local control = statsTable.States.NoControl
        local state = statsTable.PlayerStates.Self.selfCast
            

        self.Entity.SetPlayerState(state, self)
        self.stateID = self.Entity.ApplyStatus(control, self.data.duration, self)
        

        -- Invocando AddForce que injetamos na entidade no MovementComponent
        self.dashForceID = self.Entity.AddForce({
            Type = "Dash",
            Duration = self.data.duration,
            Speed = speed,
            Direction = self.Entity.GetDirection(),
            Hard = true,          
            IgnoreGravity = true, 
            Priority = 10,
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

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
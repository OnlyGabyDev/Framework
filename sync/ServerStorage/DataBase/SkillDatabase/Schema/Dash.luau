local ServerStorage = game:GetService("ServerStorage")

local Skill = {

data = {
	cooldown = 2,
	duration = 0.15,
	castTime = 0,
	speed = 150,
	anim  = "anim",
},

callbacks = {
	onStart = function(self)
        self.stateID = nil
        self.dashForceID = nil

        local statsTable = self.statusTable
        local control = statsTable.States.NoControl
        local state = statsTable.PlayerStates.Self.selfCast
            
        -- PlayerStates usam a API SetPlayerState (CombatComponent)
        self.Entity.SetPlayerState(state, self)
        
        -- Status normais usam ApplyStatus (StatusComponent)
        self.stateID = self.Entity.ApplyStatus(control, 5, self)
        
        local dir = self.Entity.GetDirection()
        if dir.Magnitude == 0 then
            local wrapper = self.Entity.GetCharacterWrapper()
            dir = wrapper and wrapper:GetRoot().CFrame.LookVector or Vector3.new(0, 0, -1)
        end

        local speed = self.data.speed
        
        -- Invocando AddForce que injetamos na entidade no MovementComponent
        self.dashForceID = self.Entity.AddForce({
            Type = "Dash",
            Duration = self.data.duration,
            Speed = speed,
            Direction = dir.Unit,
            Hard = true,          
            IgnoreGravity = true, 
            Priority = 10         
        })
	end,

	onEnd = function(self)
        self.Entity.RemovePlayerState()
        if self.stateID then
            self.Entity.RemoveStatusByID(self.stateID)
        end
        if self.dashForceID then
            self.Entity.RemoveForce(self.dashForceID)
        end
	end,
	
	onCancel = function(self)
        self.Entity.RemovePlayerState()
        if self.stateID then
            self.Entity.RemoveStatusByID(self.stateID)
        end
        if self.dashForceID then
            self.Entity.RemoveForce(self.dashForceID)
        end
	end,
}
}
return Skill
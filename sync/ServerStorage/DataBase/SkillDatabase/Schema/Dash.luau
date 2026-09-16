local ServerStorage = game:GetService("ServerStorage")
local BaseSkills = require(ServerStorage.Modules.BaseSkills.BaseSkills)


local Skill = {
	



data = {
	cooldown = 2,    --2
	duration = 0.15, --0.15  
	castTime = 0,
	speed = 150,
	anim  = "anim",
},

callbacks = {
	onStart = function(self)
		
			local statsTable = self.statusTable
			
			local control = statsTable.States.noControl

			--local state = statsTable.PlayerStates.Out.cast
			local state = statsTable.PlayerStates.Self.selfCast
			 
			stateID = self.cd:ApplyStatus(state,self.ED, 9999, self)
			
			self.cd:ApplyStatus(control,self.ED,5,self,stateID)
			
			print(stateID)
			
			local dir = self.ED:getDirection()
			local speed = self.data.speed
			root = self.ED.Root
		
			
			dashDir = BaseSkills.dash(dir,speed)
			
	end,

	onStep = function(self, dt)
		
			root.CFrame = root.CFrame + dashDir * dt
			
			
	end,

	onEnd = function(self)
			self.cd:RemoveID(stateID)
	end,
	
	onCancel = function(self)
			self.cd:RemoveID(stateID)
	end,
	
   }

}

return Skill
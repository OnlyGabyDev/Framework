local ServerStorage = game:GetService("ServerStorage")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local Skill = {

	data = {
		cooldown = 1,
		duration = 5,
		castTime = 0,
		tags = {[StateTable.Enum.Tags.block] = true},
		--effects = {StateTable.Status.Bleed}
	},

	callbacks = {

	
--		# Local Utils

		clearControl = function(runner,stateID)
			runner.Entity.StopAllAnimations(0.2)
			runner.Entity.RemoveStatusByID(stateID)
			runner.Entity.RemovePlayerState()
		end,
			

		
--		# Eventos
		
		onStart = function(self)
			
--		#Referencias/vars

			--Prepara status
			local statsTable = self.statusTable
			

			local shield = statsTable:BuildEffect(statsTable.Status.StatusShield,
			StateTable.Enum.SkillBreakpoints.onTrigger,
		    function(runner,context) warn("SHIELD ATINGIDO"); return self:TriggerAction(context)
			end)

			local block = statsTable:BuildEffect(statsTable.Status.GenericBlock,
			StateTable.Enum.SkillBreakpoints.onTrigger,
			function(runner,context) return self:TriggerAction(context) 
			end)

			self.damage = 2
			
			self.M1Start = self.charLib.M1.M1Start
			self.M1S2 = self.charLib.M1.M1S2

			
			self.track = self.Entity.PlayAnimation(self.M1Start)
			self.track.Looped = false

			self.control = statsTable.States.NoControl

			self.PlayerState = statsTable.PlayerStates.Out.cast			 

			self.Entity.SetPlayerState(self.PlayerState, self)

			self.stateID = self.Entity.ApplyStatus(self.control,9999,self)			
			
			self.Entity.StartHitbox(self.data.duration)
		
			self.Entity.ApplyStatus(shield,9999,self)

			--self.blockID = self.Entity.ApplyStatus(block,9999,self)

			self.Entity.ApplyStatus(statsTable.Status.Bleed,9999,self)

			self.cleanUp = function()
				self.Entity.StopAnimation(self.M1Start,0.2)
				self.Entity.RemoveStatusByID(self.stateID)
				self.Entity.RemovePlayerState()
				self.Entity.StopHitbox()
			end

			self.Entity.OnMarker(tostring(self.M1Start), "End", function()
  			  self.cleanUp()
			end)
			
		end,
		
		
		onHit = function(self,hitResult)

			local targetEntity = hitResult.target
			
			targetEntity.TakeDamage(self.damage,self)

		end,
		

		onStep = function(self, dt)
			if self.trigger then
				self.cleanUp()
			end
		end,
		
		
		onRecast = function(self)
			self.counter += 1
			if self.counter == 2 then
				self.track = self.Entity.PlayAnimation(self.M1S2)
				self.track.Looped = false
				
				self.Entity.SetPlayerState(self.PlayerState, self)

				self.Entity.ApplyStatus(self.control, 9999, self, self.stateID)
				
				self.Entity.StartHitbox(self.data.duration,function(hitResult) self:onHit(hitResult.target, hitResult)end)
				
				self.damage = 3

				self.cleanUp = function()
					self:Stop(false)
					self.Entity.RemoveStatusByID(self.stateID)
					self.Entity.RemovePlayerState()
					self.Entity.StopHitbox()
				end

					self.Entity.OnMarker(tostring(self.M1S2), "End", function()
  					  self.cleanUp()
					end)
				
			end
		end,


		onTrigger = function(self,context)
			local dmg = context.damage
			dmg = 0 
			self.Entity.RemoveStatusByID(self.blockID)
			--task.wait(2)
			--task.defer(function()
				--context.sourceEntity.TakeDamage(5, self)
			--end)
			return dmg
		end,

		onEnd = function(self)
			self.callbacks.clearControl(self,self.stateID)
		end,
		
		onCancel = function(self)
			self.callbacks.clearControl(self,self.stateID)
		end,
		
	}

}

return Skill
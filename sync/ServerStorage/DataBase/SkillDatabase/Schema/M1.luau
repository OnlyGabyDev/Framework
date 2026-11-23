local ServerStorage = game:GetService("ServerStorage")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local ComponentKey = require(game:GetService("ServerScriptService").EntityData.ComponentsExport)

local Skill = {

	data = {
		cooldown = 1,
		-- O 2º golpe espera o cooldown do 1º e o reinicia: é isso que dá o ritmo do combo
		cooldownPolicy = { recast = StateTable.Enum.RecastPolicy.Restart },
		duration = 5,
		castTime = 0,
		tags = {[StateTable.Enum.Tags.block] = true},
		traits = { StateTable.Enum.Traits.Melee },
		-- Sem animação (os marcadores dela encerram o golpe) ou sem arma (a hitbox) o M1 não existe:
		-- numa entidade sem eles o motor recusa o cast, em vez de errar no onStart
		requires = { ComponentKey.Animation, ComponentKey.Weapon },
	},

	callbacks = {

		onStart = function(self)
			self.damage = 1
			
			local statsTable = self.statusTable
			self.control = statsTable.States.NoControl
			self.stateID = self.Entity.ApplyStatus(self.control, self.data.duration, self.Runner)
			self.Entity.SetActionState(statsTable.ActionStates.Out.cast, self.Runner)
			
			self.M1Start = self.charLib.M1.M1Start
			self.M1S2 = self.charLib.M1.M1S2
			
			self.track = self.Entity.PlayAnimation(self.M1Start)
			if self.track then self.track.Looped = false end -- nil sem Animator no rig
			
			self:StartHitbox(self.data.duration) -- a hitbox deste M1, não a da arma inteira

			self.cleanUp = function()
				if self.stateID then
					self.Entity.RemoveStatusByID(self.stateID)
					self.stateID = nil
				end
				self.Entity.RemoveActionState(self.Runner)
				self.Entity.StopAnimation(self.M1Start, 0.2)
				self:StopHitbox()
			end

			self.Entity.OnMarker(tostring(self.M1Start), "End", function()
				self.cleanUp()
			end)
		end,
		
		
		onHit = function(self, hitResult)
			local targetEntity = hitResult.target
			self:Damage(targetEntity, self.damage)
		end,
		

		onRecast = function(self)
			self.counter += 1
			if self.counter == 2 then
				local statsTable = self.statusTable
				self.stateID = self.Entity.ApplyStatus(self.control, self.data.duration, self.Runner)
				self.Entity.SetActionState(statsTable.ActionStates.Out.cast, self.Runner)
				
				self.track = self.Entity.PlayAnimation(self.M1S2)
				if self.track then self.track.Looped = false end
				
				self:StopHitbox() -- zera hitTargets do 1º golpe: o 2º pode acertar o mesmo alvo
				self:StartHitbox(self.data.duration)
				self.damage = 2

				self.cleanUp = function()
					if self.stateID then
						self.Entity.RemoveStatusByID(self.stateID)
						self.stateID = nil
					end
					self.Entity.RemoveActionState(self.Runner)
					self:Stop(false)
					self:StopHitbox()
				end

				self.Entity.OnMarker(tostring(self.M1S2), "End", function()
  				  self.cleanUp()
				end)
			end
		end,

		-- onEnd roda em qualquer fim, inclusive depois do onCancel: uma limpeza só
		onEnd = function(self)
			if self.cleanUp then self.cleanUp() end
		end,
	}

}

return Skill
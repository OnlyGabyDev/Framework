local Skill = {

	data = {
		cooldown = 1,
		duration = 1,
		castTime = 0,
		anim = "anim",
	},

	callbacks = {
		onStart = function(self)
			require(game:GetService("ReplicatedStorage").Logger).Channel("Skill1").Debug("rodando")
		end,

		onStep = function(self, dt)
		end,

		onTrigger = function(self,context)
			
		end,

		onEnd = function(self)
		end,
	}

}

return Skill
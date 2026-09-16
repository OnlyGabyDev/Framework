local Skill = {

	data = {
		cooldown = 1,
		duration = 1,
		castTime = 0,
		anim = "anim",
	},

	callbacks = {
		onStart = function(self)
			print("S1 RODANDO")
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
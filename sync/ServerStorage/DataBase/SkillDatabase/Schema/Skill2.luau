local Skill = {

	data = {
		cooldown = 5,
		duration = 1,
		castTime = 0,
		anim = "anim",
	},

	callbacks = {
		onStart = function(self)
			print("S2 RODANDO")
		end,

		onStep = function(self, dt)
		end,

		onEnd = function(self)
		end,
	}

}

return Skill
local Skill = {

	data = {
		cooldown = 50,
		duration = 1,
		castTime = 0,
		anim = "anim",
	},

	callbacks = {
		onStart = function(self)
			print("Ult rodando!")
		end,

		onStep = function(self, dt)
		end,

		onEnd = function(self)
		end,
	}

}

return Skill
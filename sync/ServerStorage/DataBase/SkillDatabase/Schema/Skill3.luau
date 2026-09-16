local Skill = {

	data = {
		cooldown = 2,
		duration = 1,
		castTime = 0,
		anim = "anim",
	},

	callbacks = {
		onStart = function(self)
			print("S3 RODANDO")
		end,

		onStep = function(self, dt)
		end,

		onEnd = function(self)
		end,
	}

}

return Skill
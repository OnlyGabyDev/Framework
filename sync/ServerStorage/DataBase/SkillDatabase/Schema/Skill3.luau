local Skill = {

	data = {
		cooldown = 2,
		duration = 1,
		castTime = 0,
		anim = "anim",
	},

	callbacks = {
		onStart = function(self)
			require(game:GetService("ReplicatedStorage").Logger).Channel("Skill3").Debug("rodando")
		end,

		onStep = function(self, dt)
		end,

		onEnd = function(self)
		end,
	}

}

return Skill
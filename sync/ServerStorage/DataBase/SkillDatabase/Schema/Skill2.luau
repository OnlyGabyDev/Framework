local Skill = {

	data = {
		cooldown = 5,
		duration = 1,
		castTime = 0,
		anim = "anim",
	},

	callbacks = {
		onStart = function(self)
			self.Entity.TakeDamage(50, self)
			self:Stop(false)
		end,

		onStep = function(self, dt)
		end,

		onEnd = function(self)
		end,
	}

}

return Skill
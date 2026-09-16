local Enum = require(script.Parent.Parent.Parent.Enum)

local Bleed = {
	data = {
		name = "Bleed", 
		category = Enum.Categories.Debuff,
		stackOnSelf = true, 
		maxStacks = 10,
		duration = 5, 
		tickRate = 0.5, 
		damage = 1,
		
		traits = {
		Enum.Traits.DOT,
		Enum.Traits.SoftCancel,
		Enum.Traits.Stackable,
		Enum.Traits.BlockBreak}
	},
	
	callbacks = {
		onStart = function(self)
			self._tickTimer = 0
		end,

		onStep = function(self, dt)

			self._tickTimer += dt
			local tickRate = self.skillData.data.tickRate or 1 
			
			if self._tickTimer >= tickRate then
				self._tickTimer = 0
				
				local damage = self.skillData.data.damage * self.counter
				self.Entity.TakeDamage(damage, self) 
			end
		end,
	}
}

return Bleed
local Enum = require(script.Parent.Parent.Parent.Enum)
local Log = require(game:GetService("ReplicatedStorage").Logger).Channel("Bleed")

local Bleed = {
	data = {
		name = "Bleed", 
		category = Enum.Categories.Debuff,
		stackOnSelf = true, 
		maxStacks = 10,
		duration = 100, 
		tickRate = 0.3, 
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
			-- O runner já está registrado quando o onStart roda: GetStatusCounter e self.counter batem.
			Log.Debug("onStart, stack atual:", self.counter)
		end,

		onRecast = function(self)
			-- Roda toda vez que uma nova stack é aplicada sobre a mesma instância
			Log.Debug("onRecast, nova stack, total:", self.counter)
			-- Se quiser checar o GetStatusCounter (agora ele funciona porque o runner já está salvo):
			Log.Debug("GetStatusCounter confirma:", self.Entity.GetStatusCounter("Bleed"))
		end,

		onStep = function(self, dt, context)
			self._tickTimer += dt
			local tickRate = self.data.tickRate or 1 
			
			if self._tickTimer >= tickRate then
				self._tickTimer = 0
				
				local damage = self.data.damage * (self.counter or 1)
				self.Entity.TakeDamage(damage, self.Runner) 
			end
		end,
	}
}

return Bleed
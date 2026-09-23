local Enum = require(script.Parent.Parent.Parent.Enum)

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
			-- O GetStatusCounter retorna 0 aqui porque o runner ainda está sendo inicializado e não foi salvo na tabela.
			-- O counter real da skill pode ser acessado via self.counter.
			warn("[Bleed] onStart - Stack atual:", self.counter)
		end,

		onRecast = function(self)
			-- Roda toda vez que uma nova stack é aplicada sobre a mesma instância
			warn("[Bleed] onRecast - Nova stack aplicada! Total:", self.counter)
			-- Se quiser checar o GetStatusCounter (agora ele funciona porque o runner já está salvo):
			warn("[Bleed] GetStatusCounter confirma:", self.Entity.GetStatusCounter("Bleed"))
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
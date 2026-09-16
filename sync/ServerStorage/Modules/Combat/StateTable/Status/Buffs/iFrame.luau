local Enum = require(script.Parent.Parent.Parent.Enum)

return {
	data = {
		name = "iFrame",
		category = Enum.Categories.Buff,
		
		tags = {
			[Enum.Tags.iFrame] = true
		},
		
		-- Define o que ignora esse buff (TrueHit ignora iFrame)
		bypassBy = {Enum.Traits.TrueHit}
	},
	
	callbacks = {}
}
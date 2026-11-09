local Enum = require(script.Parent.Parent.Parent.Enum)

return {
	data = {
		name = "StatusShield",
		category = Enum.Categories.Buff,
		
		ShieldsFrom = {Enum.Traits.DOT},
		tags = {[Enum.Tags.block] = true},
		block = { mode = Enum.BlockModes.Full }, -- barra o status que casar com o ShieldsFrom (D14)
	},
	
	callbacks = {}
}
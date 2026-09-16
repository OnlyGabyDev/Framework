local Enum = require(script.Parent.Parent.Enum)

return {
	data = {
		name = "Silence",
		category = Enum.States.Silence,
		
		tags = {
			[Enum.Tags.canCast] = false,
		},
		
		visual = {}
	},
	
	callbacks = {}
}
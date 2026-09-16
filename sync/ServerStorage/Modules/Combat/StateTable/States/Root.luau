local Enum = require(script.Parent.Parent.Enum)

return {
	data = {
		name = "Root",
		category = Enum.States.Root,
		
		tags = {
			[Enum.Tags.canMove] = false,
		},
		
		visual = {}
	},
	
	callbacks = {}
}
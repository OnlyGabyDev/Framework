local Enum = require(script.Parent.Parent.Enum)

return {
	data = {
		name = "noControl",
		category = Enum.States.NoControl,
		
		tags = {
			[Enum.Tags.canMove] = false,
			[Enum.Tags.canRotate] = false,
		},
		
		visual = {}
	},
	
	callbacks = {}
}
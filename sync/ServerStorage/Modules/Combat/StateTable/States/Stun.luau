local Enum = require(script.Parent.Parent.Enum)

return {
	data = {
		name = "Stun",
		category = Enum.States.Stun,
		
		tags = {
			[Enum.Tags.canMove] = false,
			[Enum.Tags.canRotate] = false,
			[Enum.Tags.canCast] = false
		},
		
		visual = {}
	},
	
	callbacks = {}
}
--OUT
local Enum = require(script.Parent.Parent.Enum)

return {
		cast = {
			data = {
				category = Enum.Categories.ActionState,
				exclusive = true,
				name = "Cast",
			},
			callbacks = {}
				

			},
		globalCast = {
			data = {
				category = Enum.Categories.ActionState,
				exclusive = true,
				name = "GlobalCast",
			},
			callbacks = {}
				
			},
		}
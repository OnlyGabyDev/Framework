	--SELF
	local Enum = require(script.Parent.Parent.Enum)

	return {
		selfCast = {
			data = {
				category = Enum.Categories.ActionState,
				exclusive = true,
				name = "SelfCast",
			},
			
			callbacks = {}
			
			},
		globalCast = {
			data = {
				category = Enum.Categories.ActionState,
				exclusive = true,
				name = "GlobalCast"
			},
			callbacks = {}

			},
	}
local Enum = require(script.Parent.Parent.Parent.Enum)

return {
	data = {
		name = "GenericBlock",

		category = Enum.Categories.Internal,
		
		tags = {
			[Enum.Tags.block] = true
		},
        
        ShieldsFromType = {Enum.Types.Skill},

        --dados especificos de shield, como apenas dano fisico, só DOT, etc...
        ShieldsFrom = {},

		traits = {Enum.Traits.Unbreakable}
	},
	
    --função de exemplo, mas ela pode ser injetada pela skill que aplica o block e redirecionar o trigger pra si mesma
	callbacks = {}
}
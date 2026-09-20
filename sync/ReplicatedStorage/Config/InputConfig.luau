--[[
	InputConfig — tabela única de bindings. Intent -> códigos físicos

	- Qualquer dispositivo, qualquer quantidade: teclado, mouse e gamepad convivem na mesma lista.
	  (KeyCode e UserInputType são valores de enum distintos, então não precisa separar por dispositivo.)
	- Troca de teclas pelo usuário: InputService.Rebind(intent, codes)
	- Botões de tela (mobile) não entram aqui: qualquer GuiButton com a tag `ButtonTag` e o atributo
	  `ButtonIntentAttribute` vira fonte da intent, sem código.

	Os defaults de gamepad são um ponto de partida: ButtonA/ButtonR3 etc. já têm uso no PlayerModule padrão.
]]

local Intents = require(script.Parent.Parent.Input.Intents)
local Id = Intents.Id

return {
	Bindings = {
		[Id.Primary] = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 },
		[Id.Dash] = { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonB },
		[Id.Ability1] = { Enum.KeyCode.One, Enum.KeyCode.ButtonX },
		[Id.Ability2] = { Enum.KeyCode.Two, Enum.KeyCode.ButtonY },
		[Id.Ability3] = { Enum.KeyCode.Three, Enum.KeyCode.ButtonL1 },
		[Id.Ultimate] = { Enum.KeyCode.Four, Enum.KeyCode.ButtonR1 },
	},

	ButtonTag = "InputButton",
	ButtonIntentAttribute = "Intent",
}

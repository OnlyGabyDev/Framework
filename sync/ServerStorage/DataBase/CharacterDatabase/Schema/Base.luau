local ServerStorage = game:GetService("ServerStorage")
local SkillDB = require(ServerStorage.DataBase.SkillDatabase)
local Keys = SkillDB.Keys

return {
	Stats = {
		MaxHP = 100,
		Speed = 2000,
		JumpForce = 50,
	},
	Loadout = {
		Slots = {
			[1] = Keys.Schema.M1
		}
	},


	Weapon = "Martelo",
	attachTo = "Right Arm"
}

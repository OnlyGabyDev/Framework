local ServerStorage = game:GetService("ServerStorage")
local SkillDB = require(ServerStorage.DataBase.SkillDatabase)
local Ultimate = require(ServerStorage.DataBase.SkillDatabase.Schema.Ultimate)
local Keys = SkillDB.Keys

return {
	Stats = {
		MaxHP = 100,
		Speed = 20,
		JumpForce = 50,
	},
	Loadout = {
		Slots = {
			[1] = Keys.Schema.M1,
			[2] = Keys.Schema.Dash,
			[3] = Keys.Schema.Ultimate
		}
	},


	Weapon = "Martelo",
	attachTo = "Right Arm"
}

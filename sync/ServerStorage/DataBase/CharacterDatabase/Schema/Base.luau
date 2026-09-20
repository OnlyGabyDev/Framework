local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkillDB = require(ServerStorage.DataBase.SkillDatabase)
local Intents = require(ReplicatedStorage.Input.Intents).Id
local Keys = SkillDB.Keys

return {
	Stats = {
		MaxHP = 100,
		Speed = 20,
		JumpForce = 10,
	},
	Loadout = {
		Slots = {
			[Intents.Primary] = Keys.Schema.M1,
			[Intents.Dash] = Keys.Schema.Dash,
			[Intents.Ultimate] = Keys.Schema.Ultimate,
		}
	},


	Weapon = "Martelo",
	attachTo = "Right Arm"
}

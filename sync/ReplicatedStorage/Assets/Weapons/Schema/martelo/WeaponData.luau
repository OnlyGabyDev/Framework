local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Intents = require(ReplicatedStorage.Input.Intents).Id
local SkillDB = require(ServerStorage.DataBase.SkillDatabase)
local Keys = SkillDB.Keys

return {
	BaseName = "Martelo",
	DefaultMode = "Dual",

	Modes = {
		Dual = {
			AttachPoints = {
				primary = "Right Arm",
				secondary = "Left Arm"
			},
			AnimSet = "DualBlades",
			FXSet = "DualBlades",
			Loadout = {
				Slots = {
					[Intents.Ability1] = Keys.Schema.Skill2 -- placeholder para o teste
				}
			},
			Skills = "DualSkills",  
			TransformTime = 0.5,
			TransformAnim = "MergeBlades"
		},

		Merged = {
			AttachPoints = {
				primary = "Right Arm"
			},
			AnimSet = "MergedBlade",
			FXSet = "MergedBlade",
			Loadout = {
				Slots = {
					[Intents.Ability1] = Keys.Schema.Skill2 -- placeholder diferente?
				}
			},
			Skills = "MergedSkills",
			TransformTime = 0.5,
			TransformAnim = "SplitBlades"
		}
	}
}
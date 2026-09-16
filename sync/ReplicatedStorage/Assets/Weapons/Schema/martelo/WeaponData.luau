return {
	BaseName = "HunterBlades",
	DefaultMode = "Dual",

	Modes = {
		Dual = {
			AttachPoints = {
				primary = "Right Arm",
				secondary = "Left Arm"
			},
			AnimSet = "DualBlades",
			Skills = "DualSkills",  
			TransformTime = 0.5,
			TransformAnim = "MergeBlades"
		},

		Merged = {
			AttachPoints = {
				primary = "Right Arm"
			},
			AnimSet = "MergedBlade",
			Skills = "MergedSkills",
			TransformTime = 0.5,
			TransformAnim = "SplitBlades"
		}
	}
}
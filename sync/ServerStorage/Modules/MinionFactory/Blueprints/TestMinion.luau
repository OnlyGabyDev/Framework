return {
	Components = { "Character", "Health", "Movement" },
	Configs = {},
	BuildModel = function(cframe: CFrame): Model
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(1.5, 1.5, 1)
		root.Color = Color3.fromRGB(230, 180, 60)
		root.CFrame = cframe
		root.Parent = model
		model.PrimaryPart = root
		return model
	end,
}

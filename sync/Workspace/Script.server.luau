local ServerScriptService = game:GetService("ServerScriptService")
local DataManager = require(game.ServerScriptService.EntityData.DataManager)
local component = require(ServerScriptService.EntityData.ComponentsExport)


local components = {
	Character = component.Character,
	Health = component.Health,
    Status = component.Status
}

for i = 0,0,1 do
    model = Instance.new("Model")
    model.Parent = workspace

    local part1 = Instance.new("Part")
    part1.Name = "BasePart"
    num3 = math.random(1,15)
    num1 = math.random(1,15)
    num2 = math.random(1,15)
    part1.Size = Vector3.new(num1, num2, num3)
    part1.Position = Vector3.new(0, 1, 0) 
    part1.Anchored = false
    part1.BrickColor = BrickColor.new("Bright yellow")
    part1.Parent = model

    DataManager.Create(model, components)
end



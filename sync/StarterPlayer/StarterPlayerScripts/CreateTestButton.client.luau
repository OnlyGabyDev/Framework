local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local InputConfig = require(ReplicatedStorage.Config.InputConfig)

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("CooldownGUI")

-- Verifica se já existe um botão de teste para não duplicar
local exists = false
for _, btn in pairs(gui:GetDescendants()) do
	if btn:IsA("GuiButton") and btn:GetAttribute(InputConfig.ButtonIntentAttribute) == "Ability3" then
		exists = true
		break
	end
end

if not exists then
	local testButton = Instance.new("TextButton")
	testButton.Name = "TestWeaponTransformButton"
	testButton.Size = UDim2.fromOffset(100, 50)
	testButton.Position = UDim2.new(1, -120, 0, 20)
	testButton.AnchorPoint = Vector2.new(1, 0)
	testButton.Text = "Trocar Modo (3)"
	testButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	testButton.TextColor3 = Color3.new(1, 1, 1)
	
	-- Adiciona os atributos e tags que o sistema do framework exige
	testButton:SetAttribute(InputConfig.ButtonIntentAttribute, "Ability3")
	CollectionService:AddTag(testButton, InputConfig.ButtonTag)
	
	-- Barra de cooldown fake/interna (precisa ter um Frame filho pra UI de cooldown funcionar)
	local cdBar = Instance.new("Frame")
	cdBar.Name = "Frame"
	cdBar.Size = UDim2.fromScale(1, 1)
	cdBar.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	cdBar.BackgroundTransparency = 0.5
	cdBar.Parent = testButton
	
	testButton.Parent = gui
end

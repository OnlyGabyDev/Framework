--[[
	CooldownUIController
	Recebe (intent, cooldown) do servidor e anima a barra do botão daquela intent.
	O botão é achado pelo mesmo atributo que o InputService usa (InputConfig.ButtonIntentAttribute):
	a UI não conhece nome de skill nem de botão, só o slot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local InputConfig = require(ReplicatedStorage.Config.InputConfig)

local SkillFired = ReplicatedStorage.RemoteEvents.SkillFired
local gui = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("CooldownGUI")

local activeTweens = setmetatable({}, { __mode = "k" }) -- [barra] = Tween 

-- GetTagged também devolve os templates de StarterGui, por isso o filtro por descendência da GUI viva.
local function findButton(intent: string): GuiButton?
	for _, button in CollectionService:GetTagged(InputConfig.ButtonTag) do
		if button:IsDescendantOf(gui) and button:GetAttribute(InputConfig.ButtonIntentAttribute) == intent then
			return button
		end
	end
	return nil
end

SkillFired.OnClientEvent:Connect(function(intent: string, cooldown: number)
	local button = findButton(intent)
	local bar = button and button:FindFirstChild("Frame")
	if not bar then
		return
	end

	if activeTweens[bar] then
		activeTweens[bar]:Cancel()
	end

	bar.Size = UDim2.fromScale(1, 1)

	local tween = TweenService:Create(bar, TweenInfo.new(cooldown, Enum.EasingStyle.Linear), {
		Size = UDim2.fromScale(1, 0),
	})
	activeTweens[bar] = tween
	tween:Play()
end)

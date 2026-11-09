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

local chargeState = setmetatable({}, { __mode = "k" }) -- [botão] = { charges, max, duration, token }

-- Rótulo "n/m" das cargas no canto do botão (criado na primeira vez que a skill tem cargas)
local function chargeLabel(button: GuiButton): TextLabel
	local label = button:FindFirstChild("Charges") :: TextLabel?
	if not label then
		label = Instance.new("TextLabel")
		label.Name = "Charges"
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(1, 1)
		label.Position = UDim2.fromScale(1, 1)
		label.Size = UDim2.fromScale(0.5, 0.35)
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.ZIndex = 10
		label.Parent = button
	end
	return label
end

local function animateBar(bar: GuiObject, seconds: number)
	if activeTweens[bar] then
		activeTweens[bar]:Cancel()
	end
	bar.Size = UDim2.fromScale(1, 1)
	local tween = TweenService:Create(bar, TweenInfo.new(seconds, Enum.EasingStyle.Linear), {
		Size = UDim2.fromScale(1, 0),
	})
	activeTweens[bar] = tween
	tween:Play()
end

-- Recarga prevista no cliente: a cada recarga que termina, +1 carga e emenda a próxima
-- (o servidor é a autoridade; cada SkillFired novo corrige o estado)
local function scheduleRecharge(button, bar, state, remaining)
	state.token += 1
	local token = state.token
	if state.charges >= state.max or not remaining or remaining <= 0 then return end
	if bar then animateBar(bar, remaining) end
	task.delay(remaining, function()
		if state.token ~= token then return end
		state.charges = math.min(state.max, state.charges + 1)
		chargeLabel(button).Text = string.format("%d/%d", state.charges, state.max)
		scheduleRecharge(button, bar, state, state.duration)
	end)
end

SkillFired.OnClientEvent:Connect(function(intent: string, cooldown: number, charges: number?, maxCharges: number?,
	rechargeRemaining: number?, rechargeDuration: number?)
	local button = findButton(intent)
	local bar = button and button:FindFirstChild("Frame")
	if not button then
		return
	end

	if maxCharges then
		local state = chargeState[button] or { token = 0 }
		chargeState[button] = state
		state.charges, state.max, state.duration = charges or 0, maxCharges, rechargeDuration
		chargeLabel(button).Text = string.format("%d/%d", state.charges, state.max)
		scheduleRecharge(button, bar, state, rechargeRemaining)
		return
	end

	if bar then
		animateBar(bar, cooldown)
	end
end)

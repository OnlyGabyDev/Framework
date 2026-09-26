local Debris = game:GetService("Debris")

local Registry = {}

Registry.GenericImpact = function(data: {[string]: any})
	local position = data.Position :: Vector3?
	if not position then return end

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Lifetime = NumberRange.new(0.3, 1.3) -- Vivem por 1 minuto
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(1, 2) -- Bem mais devagar pra não sumirem da tela
	emitter.Size = NumberSequence.new(2) -- GIGANTES
	emitter.LightEmission = 1 -- Brilhantes
	emitter.Brightness = 5
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 200, 50)) -- Amarelas
	emitter.SpreadAngle = Vector2.new(180, 180) -- Espalha pra todos os lados
	emitter.Parent = anchor

	emitter:Emit(data.Count or 30) -- Mais faíscas
	Debris:AddItem(anchor, 65) -- Não destrói a âncora antes da partícula sumir
end

return Registry

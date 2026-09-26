local ServerStorage = game:GetService("ServerStorage")
local AreaEffect = require(ServerStorage.Modules.Combat.AreaEffect)
local AreaBehaviors = require(ServerStorage.Modules.Combat.AreaBehaviors)

-- Script de demo do Ventilador (spawn de objeto no mapa)

-- Dimensões da zona de push
local PUSH_OFFSET = 10
local PUSH_WIDTH = 10
local PUSH_HEIGHT = 10
local PUSH_DEPTH = 20
local PUSH_SPEED = 30

-- Dimensões da zona de pull
local PULL_OFFSET = 10
local PULL_WIDTH = 10
local PULL_HEIGHT = 10
local PULL_DEPTH = 20
local PULL_SPEED = 20

local function SpawnVentilador(position: Vector3)
    -- Cria o part visual do ventilador
    local fanPart = Instance.new("Part")
    fanPart.Name = "Ventilador"
    fanPart.Size = Vector3.new(4, 4, 1)
    fanPart.Position = position
    fanPart.Anchored = true
    fanPart.BrickColor = BrickColor.new("Bright blue")
    fanPart.Parent = workspace

    -- Indica a frente
    local decal = Instance.new("Decal")
    decal.Face = Enum.NormalId.Front
    decal.Texture = "rbxassetid://6023565652" -- Uma textura qualquer pra saber pra onde aponta
    decal.Parent = fanPart

    local function fanCFrame()
        return fanPart.CFrame
    end

    -- Cria a zona de Push (Frente do ventilador - LookVector é * CFrame.new(0, 0, -Z))
    local pushZone = AreaEffect.new(
        function() return fanCFrame() * CFrame.new(0, 0, -PUSH_OFFSET) end,
        "Box", 
        Vector3.new(PUSH_WIDTH, PUSH_HEIGHT, PUSH_DEPTH), 
        10
    )
    
    pushZone:OnStay(function(entity)
        AreaBehaviors.DirectionalForce(entity, function() return fanCFrame().LookVector end, PUSH_SPEED, "FanPush", { MaxForce = 35000 })
    end)
    pushZone:Start()

    -- Cria a zona de Pull (Traseira do ventilador - LookVector negativo)
    local pullZone = AreaEffect.new(
        function() return fanCFrame() * CFrame.new(0, 0, PULL_OFFSET) end,
        "Box", 
        Vector3.new(PULL_WIDTH, PULL_HEIGHT, PULL_DEPTH), 
        10
    )
    
    pullZone:OnStay(function(entity)
        AreaBehaviors.DirectionalForce(entity, function() return -fanCFrame().LookVector end, PULL_SPEED, "FanPull", { MaxForce = 35000 })
    end)
    pullZone:Start()

    -- Cleanup atrelado ao ciclo de vida da Part (se for deletada, limpa as zonas)
    fanPart.Destroying:Connect(function()
        pushZone:Stop()
        pullZone:Stop()
    end)
    
    -- Deixa ele girando devagarzinho pra demonstrar a rotação orgânica!
    task.spawn(function()
        while fanPart.Parent do
            fanPart.CFrame = fanPart.CFrame * CFrame.Angles(0, math.rad(1), 0)
            task.wait(0.05)
        end
    end)
    
    return fanPart
end

-- Espera um pouco pro mundo carregar e o player spawnar e depois spawna o ventilador
task.wait(3)
SpawnVentilador(Vector3.new(0, 5, -30))
print("[VentiladorDemo] Ventilador spawnado em (0, 5, -30). Ele irá girar sozinho para testar a direção da força em tempo real.")

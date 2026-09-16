local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local DataManager = require(ServerScriptService.EntityData.DataManager)
local Handler = ServerScriptService.Modules.SkillHandler
local StatusTable = require(ServerStorage.Modules.Combat.StateTable)
local DataManager = require(game.ServerScriptService.EntityData.DataManager)
local component = require(ServerScriptService.EntityData.ComponentsExport)
local AntiCheat = require(ServerScriptService.Modules.GlobalAntiCheat)

local PlayerComponents = {
	Character = component.Character,
	Combat = component.Combat,
	Health = component.Health,
	Weapon = component.Weapon,
	Movement = component.Movement,
	Status = component.Status,
	Animation = component.Animation,
	Attributes = component.Attributes
}


Players.PlayerAdded:Connect(function(player)

    local function onCharacterAdded(character)
        DataManager.Create({
            Model = character,
            Player = player,
        }, PlayerComponents)
		AntiCheat.Register(player)
    end

    -- primeiro spawn
    if player.Character then
        onCharacterAdded(player.Character)
    end

    -- respawns
    player.CharacterAdded:Connect(onCharacterAdded)
end)

Players.PlayerRemoving:Connect(function(player)
    DataManager.Remove(player)
	AntiCheat.Unregister(player)
end)


--[[
Players.PlayerAdded:Connect(function(player)
	

	player.Chatted:Connect(function(msg)
		if msg == ";bleed" then
			local ED = DataManager.Get(player)
			
			if not ED then
				warn("EntityData não encontrado para:", player.Name)
				return
			end

			local Status = StateTable.Status.Bleed
			local duration = Status.data.duration

			local cd = ED.CombatData
			
			
			cd.ApplyStatus(Status,ED,nil,nil)
			
			print ("Stacks: ",cd:Count(Status))
			
		end
	end)
	
end)

local function toggleMoveBlock(player)
	local ED = DataManager.Get(player)
	local cd = ED.CombatData

	if cd.GetStatus("Stun") then
		warn("Stun removido!")
		cd:Remove({ data = { name = "Stun" } })
	else
		warn("Stun aplicado!")
		cd.ApplyStatus(StatusTable.States.stun, ED, 5) -- 5 segundos
	end
end

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(msg)
		if msg == ";moveblock" then
			toggleMoveBlock(player)
		end
	end)
end)




-- FUNÇÕES MUITO IMPORTANTES POR FAVOR NÃO APAGAR É SÉRIO --

--[[

local function convertToRagdoll(model)
	for _, desc in pairs(model:GetDescendants()) do
		if desc:IsA("Motor6D") then
			local part0 = desc.Part0
			local part1 = desc.Part1
			local attachment0 = Instance.new("Attachment", part0)
			local attachment1 = Instance.new("Attachment", part1)
			attachment0.CFrame = desc.C0
			attachment1.CFrame = desc.C1

			local socket = Instance.new("BallSocketConstraint")
			socket.Attachment0 = attachment0
			socket.Attachment1 = attachment1
			socket.Parent = part0

			desc:Destroy()
		end
	end
end



local function applyRandomForce(model)
	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local force = Instance.new("BodyVelocity")
	force.Velocity = Vector3.new(0, -math.random(80, 200), 0)
	force.MaxForce = Vector3.new(0, math.huge, 0)
	force.P = 5000
	force.Parent = rootPart


	game.Debris:AddItem(force, 1)
end


local function scaleModel(model, scale)
	for _, part in pairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Size *= scale
			part.Position *= scale
		end
	end
end



local Players = game:GetService("Players")



Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local root = character:WaitForChild("HumanoidRootPart")
		
		
		local rig1 = workspace:FindFirstChild("SchemaRig")
		local rig2 = workspace:FindFirstChild("AshleyRig")
		local rig3 = workspace:FindFirstChild("VanhousenRig")
		
		
		

		

		local rigTemplate = workspace:FindFirstChild("SchemaRig")
		if rigTemplate then
			
			rigs = {
				rig1,
				rig2,
				rig3,
			}
			
			while true do 
				wait(0.2)
				local number = math.random(1,#rigs)
				local height = math.random(5,100)
				rigTemplate = rigs[number]
			local clone = rigTemplate:Clone() 
				
				-- 🔀 Escala aleatória (entre 0.7x e 1.5x do tamanho original)
				local scale = math.random(10, 400) / 100
				--scaleModel(clone, scale)

				--clone:PivotTo(CFrame.new(root.Position + Vector3.new(0, 50 * 5, 0)))
				clone.Parent = workspace

				convertToRagdoll(clone)

				for _, part in ipairs(clone:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Anchored = false
						part.CanCollide = true
						part.Massless = false
					end
				end

				-- 💥 Aplica força para simular impacto
				applyRandomForce(clone)
			end
		end
	end)
end)
]]
--[[
Prova de integração ampla: Hunter guiado por AIComponent caça a entidade viva 
mais próxima. Possui o jogador aos 5 segundos, criando uma "Possessão Dupla": 
o jogador controla o Hunter, e a IA do Hunter assume o corpo do jogador! 
Adicionalmente, 2 minions idênticos ao jogador em miniatura são spawnados.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local DataManager = require(ServerScriptService.EntityData.DataManager)
local SkillHandler = require(ServerScriptService.Modules.SkillHandler)
local SkillRunner = require(ServerScriptService.Modules.SkillRunner)
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local BaseSkills = require(ServerStorage.DataBase.SkillDatabase.BaseSkills)
local VFXManager = require(ServerScriptService.Modules.VFX.VFXManager)

local function isAlive(core)
	return core:HasComponent(core.ComponentKey.Health) and core.GetHP() > 0
end

local function findNearestHealthEntity(fromEntity: any, maxRange: number, ignoreSet: {[any]: boolean}): any?
	local myPos = fromEntity.GetCFrame().Position
	local best, bestDist = nil, maxRange
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:IsA("Model") and obj:GetAttribute("EntityID") then
			local core = DataManager.Get(obj)
			if core and core ~= fromEntity and isAlive(core) and not ignoreSet[core] then
				local root = core.GetRoot and core.GetRoot()
				if root then
					local dist = (root.Position - myPos).Magnitude
					if dist < bestDist then
						best, bestDist = core, dist
					end
				end
			end
		end
	end
	return best
end

-- ===== Skills inline =====
local HunterDash = {
	data = { cooldown = 2, duration = 0.4, castTime = 0 },
	callbacks = {
		onStart = function(self)
			local dir = self.Entity.GetDirection()
			if dir.Magnitude < 0.1 then dir = self.Entity.GetLastDirection() end
			self.forceID = self.Entity.AddForce({
				Type = "HunterDash", Duration = self.data.duration, Speed = 45,
				Direction = dir, Hard = true, IgnoreGravity = true, Priority = 10,
			})
			BaseSkills.ComboWindow.Mark(self.Entity, "HunterCombo", 1, { Direction = dir }, self.Runner)
		end,
		onEnd = function(self)
			if self.forceID then self.Entity.RemoveForce(self.forceID) end
		end,
	},
}

local HunterFinisher = {
	data = { cooldown = 0.5, duration = 1.5, castTime = 0 },
	callbacks = {
		onStart = function(self)
			self.comboed = BaseSkills.ComboWindow.Consume(self.Entity, "HunterCombo") ~= nil
			
			local ignore = self.Entity.HunterIgnoreSet or {}
			self.target = findNearestHealthEntity(self.Entity, 8, ignore)
			if not self.target then self:Stop(false); return end

			if self.comboed then
				self.grabForceID = self.target.AddForce({
					Type = "HunterGrab", Duration = self.data.duration, Hard = true,
					IgnoreGravity = true, RequiresControl = false,
					FollowTarget = function() return self.Entity.GetRoot() end,
					FollowOffset = Vector3.new(0, 0, -3), FollowOffsetIsLocal = true,
					FollowResponsiveness = 18, FollowMaxSpeed = 80,
				})
			end

			local damage = self.comboed and 5 or 1 -- Dano baixo para demorar a matar
			local success = self.target.TakeDamage(damage, self.Runner)
			
			-- Simula um trigger "onHit" pros buffs escutarem
			self.Entity:Emit(
				StateTable.Enum.Roles.OUT,
				StateTable.Enum.Breakpoints.onHit,
				{ targetEntity = self.target, sourceSkill = self, traits = { [StateTable.Enum.Traits.Melee] = true } }
			)

			if success then
				VFXManager.PlayAll("GenericImpact", {Position = self.target.GetRoot().Position})
				
				if not isAlive(self.target) then
					for _, part in ipairs(self.target.Entity:GetDescendants()) do
						if part:IsA("BasePart") then
							part.Color = Color3.fromRGB(40, 40, 200) -- Azul (Morto)
						end
					end
				end
			end
		end,
		onEnd = function(self)
			if self.grabForceID and self.target then
				self.target.RemoveForce(self.grabForceID)
			end
		end,
	},
}
-- ===== Setup =====

local jumpEvent = Instance.new("RemoteEvent")
jumpEvent.Name = "RequestJump"
jumpEvent.Parent = game:GetService("ReplicatedStorage").RemoteEvents

jumpEvent.OnServerEvent:Connect(function(plr)
	local ID = AntiCheat.GetEntityID(plr)
	if not ID then return end
	local entityCore = DataManager.Get(ID)
	if not entityCore then return end
	local root = entityCore.GetRoot and entityCore.GetRoot()
	if root and root.Parent then
		local hum = root.Parent:FindFirstChildOfClass("Humanoid")
		if hum then hum.Jump = true end
	end
end)

local function buildDummyModel(cframe: CFrame, color: Color3): Model
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Color = color
	root.CFrame = cframe
	root.Parent = model
	local hum = Instance.new("Humanoid")
	hum.Parent = model
	model.PrimaryPart = root
	return model
end

local hunterModel = buildDummyModel(CFrame.new(0, 5, 0), Color3.fromRGB(200, 40, 40))
hunterModel.Parent = workspace
local hunter = DataManager.Create(hunterModel, {
	"Character", "Health", "Movement", "Status", "Control", "AI"
})
hunter.SetMovement()
hunter.HunterIgnoreSet = {}

local targetModel = buildDummyModel(CFrame.new(0, 5, -20), Color3.fromRGB(40, 200, 40))
targetModel.Parent = workspace
local target = DataManager.Create(targetModel, { "Character", "Health", "Movement", "Status" })
target.SetMovement()
target.ApplyStatus(StateTable.Status.GenericBlock, { Duration = 30 })

local function createHunterBrain()
	local sinceLastAction = 0
	return function(entity, dt)
		sinceLastAction += dt
		local ignore = entity.HunterIgnoreSet or {}
		
		local nearestTarget = findNearestHealthEntity(entity, 40, ignore)
		if not nearestTarget then return end

		local toTarget = nearestTarget.GetRoot().Position - entity.GetRoot().Position
		local flatToTarget = Vector3.new(toTarget.X, 0, toTarget.Z)

		SkillHandler.HandleMovementInput(entity.ID, flatToTarget)
		SkillHandler.HandleLookInput(entity.ID, flatToTarget)

		if flatToTarget.Magnitude > 6 then return end
		if sinceLastAction < 2 then return end
		sinceLastAction = 0

		if entity:HasComponent(entity.ComponentKey.Combat) then
			local Intents = require(game:GetService("ReplicatedStorage").Input.Intents)
			
			-- Usa Dash para encurtar distância ou às vezes aleatoriamente, senão espanca de M1
			if flatToTarget.Magnitude > 15 or math.random() < 0.3 then
				SkillHandler.HandleIntent(entity.ID, Intents.NewEvent(Intents.Id.Dash, Intents.Kind.Activate, Intents.Gesture.Press))
			else
				SkillHandler.HandleIntent(entity.ID, Intents.NewEvent(Intents.Id.Primary, Intents.Kind.Activate, Intents.Gesture.Press))
			end
		else
			SkillRunner.new(HunterDash, entity, "HunterDash", StateTable.Enum.Types.Skill):start()
			task.delay(0.5, function()
				SkillRunner.new(HunterFinisher, entity, "HunterFinisher", StateTable.Enum.Types.Skill):start()
			end)
		end
	end
end

hunter.SetBrain(createHunterBrain())

task.delay(5, function()
	local player = Players:GetPlayers()[1]
	if not player then return end

	local playerCore = DataManager.Get("Player_" .. player.UserId)
	local playerChar = player.Character

	warn("[GrandDemo] Possessão Dupla! Você é o bloco vermelho. Seu corpo virou IA.")
	hunter.SetEnabled(false) -- Desliga a IA do Hunter pra ele parar de lutar com você
	hunter.Possess({ Player = player })
	-- O corpo original do player ganha a mente da IA e ignora o Hunter
	if playerCore then
		-- Puxa a ownership pro servidor pro client não conseguir mover o próprio corpo
		local root = playerCore.GetRoot and playerCore.GetRoot()
		if root then root:SetNetworkOwner(nil) end

		playerCore:AddComponent(playerCore.ComponentKey.AI, {}, true)
		playerCore.HunterIgnoreSet = { [hunter] = true }
		hunter.HunterIgnoreSet[playerCore] = true
		playerCore.SetBrain(createHunterBrain())
	end

	-- Clona o jogador como minions menores
	for i = 1, 2 do
		if playerChar then
			playerChar.Archivable = true
			local clone = playerChar:Clone()
			clone.Parent = workspace
			clone:PivotTo(hunter.GetCFrame() * CFrame.new(i * 3, 0, 5))
			clone:ScaleTo(0.5)
			
			local minion = DataManager.Create(clone, {"Character", "Health", "Movement", "Status", "AI"}, nil, hunter)
			if minion then
				minion.SetMovement()
				minion.HunterIgnoreSet = { [hunter] = true, [playerCore] = true }
				hunter.HunterIgnoreSet[minion] = true
				playerCore.HunterIgnoreSet[minion] = true
				minion.SetBrain(createHunterBrain())
			end
		end
	end

	task.wait(30)
	
	warn("[GrandDemo] Devolvendo tudo ao normal.")
	hunter.Release()
	hunter.SetEnabled(true) -- Liga a IA do Hunter de volta
	if playerCore then
		playerCore:RemoveComponent(playerCore.ComponentKey.AI)
		local root = playerCore.GetRoot and playerCore.GetRoot()
		if root then root:SetNetworkOwner(player) end
	end
end)

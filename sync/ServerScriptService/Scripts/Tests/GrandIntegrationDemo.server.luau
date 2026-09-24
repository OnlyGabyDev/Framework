--[[
Prova de integração ampla, não demo de produção: um Hunter guiado por
AIComponent caça a entidade viva mais próxima usando o MESMO pipeline de
input que um player usa (SkillHandler), invoca 2 minions (Fork de
TriggerSet via MinionFactory), executa Dash->Finisher (ComboWindow) e prende
o alvo (Tether) no finisher quando combado. Demonstra possessão real
(ControlComponent) se houver um player conectado.

Ignora CombatComponent/loadout de propósito — chamar SkillRunner direto é
válido: SkillHandler.activate só RESOLVE qual skill rodar a partir de um
loadout, não é o único caminho legítimo de iniciar uma. Fabricar uma pasta
CharData inteira só pra este smoke test seria esforço fora de escopo.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local DataManager = require(ServerScriptService.EntityData.DataManager)
local SkillHandler = require(ServerScriptService.Modules.SkillHandler)
local SkillRunner = require(ServerScriptService.Modules.SkillRunner)
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local BaseSkills = require(ServerStorage.DataBase.SkillDatabase.BaseSkills)
local MinionFactory = require(ServerStorage.Modules.MinionFactory)

local function findNearestHealthEntity(fromEntity: any, maxRange: number): any?
	local myPos = fromEntity.GetCFrame().Position
	local best, bestDist = nil, maxRange
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:IsA("Model") and obj:GetAttribute("EntityID") then
			local core = DataManager.Get(obj)
			if core and core ~= fromEntity and core:HasComponent(core.ComponentKey.Health) then
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
			self.target = findNearestHealthEntity(self.Entity, 8)
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

			local damage = self.comboed and 15 or 5
			local success = self.target.TakeDamage(damage, self.Runner)
			warn(string.format("[HunterFinisher] Combo=%s DanoAplicado=%s", tostring(self.comboed), tostring(success)))
		end,
		onEnd = function(self)
			if self.grabForceID and self.target then
				self.target.RemoveForce(self.grabForceID)
			end
		end,
	},
}

-- ===== Setup =====

local function buildDummyModel(cframe: CFrame, color: Color3): Model
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Color = color
	root.CFrame = cframe
	root.Parent = model
	model.PrimaryPart = root
	return model
end

local hunterModel = buildDummyModel(CFrame.new(0, 5, 0), Color3.fromRGB(200, 40, 40))
hunterModel.Parent = workspace
local hunter = DataManager.Create(hunterModel, {
	"Character", "Health", "Movement", "Status", "Control", "AI"
})
hunter.SetMovement()

local targetModel = buildDummyModel(CFrame.new(0, 5, -20), Color3.fromRGB(40, 200, 40))
targetModel.Parent = workspace
local target = DataManager.Create(targetModel, { "Character", "Health", "Movement", "Status" })
target.SetMovement()
target.ApplyStatus(StateTable.Status.GenericBlock, { Duration = 30 })

for i = 1, 2 do
	local minion = MinionFactory.Spawn("TestMinion", CFrame.new(i * 3, 5, 5), hunter)
	if minion then
		minion.SetMovement()
		minion:AddComponent(minion.ComponentKey.AI, {}, true)
		minion.SetBrain(function(entity, dt)
			local nearestTarget = findNearestHealthEntity(entity, 30)
			if nearestTarget then
				local dir = nearestTarget.GetRoot().Position - entity.GetRoot().Position
				SkillHandler.HandleMovementInput(entity.ID, dir)
			end
		end)
	end
end

hunter:Listen({
	Role = StateTable.Enum.Roles.OUT,
	Breakpoint = StateTable.Enum.Breakpoints.onHit,
	Inherit = { Generations = 1 },
	Priority = 0,
	Action = function()
		warn("[GrandDemo] Hunter OUVIU um hit herdado de um minion — Fork de TriggerSet confirmado")
	end,
})

local sinceLastAction = 0
hunter.SetBrain(function(entity, dt)
	sinceLastAction += dt

	local nearestTarget = findNearestHealthEntity(entity, 40)
	if not nearestTarget then return end

	local toTarget = nearestTarget.GetRoot().Position - entity.GetRoot().Position
	local flatToTarget = Vector3.new(toTarget.X, 0, toTarget.Z)

	SkillHandler.HandleMovementInput(entity.ID, flatToTarget)
	SkillHandler.HandleLookInput(entity.ID, flatToTarget)

	if flatToTarget.Magnitude > 6 then return end
	if sinceLastAction < 2 then return end
	sinceLastAction = 0

	SkillRunner.new(HunterDash, entity, "HunterDash", StateTable.Enum.Types.Skill):start()

	task.delay(0.5, function()
		SkillRunner.new(HunterFinisher, entity, "HunterFinisher", StateTable.Enum.Types.Skill):start()
	end)
end)

task.delay(5, function()
	local player = Players:GetPlayers()[1]
	if not player then
		warn("[GrandDemo] Nenhum player conectado — pulando demo de possessão real")
		return
	end

	warn("[GrandDemo] Possuindo Hunter com", player.Name, "por 4 segundos (IA pausa)")
	hunter.Possess({ Player = player })
	task.wait(4)
	warn("[GrandDemo] Devolvendo Hunter pra IA")
	hunter.Release()
end)

warn("[GrandDemo] Cenário no ar: Hunter (vermelho) caça alvo (verde), minions auxiliares, dash+finisher com combo/tether.")

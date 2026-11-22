--[[
TestTargets — transforma os rigs e dummies de teste do Workspace em entidades no Play, para usar
skills neles (a Ultimate agarra, o M1 acerta). Ferramenta de teste: não vai para produção.

Quem entra:
- todo Model com a tag FW_TestTarget (CollectionService; inclusive os que entrarem depois);
- os filhos de Workspace.Dummies e os rigs de animação listados em RIGS.

Cada alvo vira entidade com Character, Health, Status e Movement (NPC: física do servidor, anda
pelo Humanoid), tem o HumanoidRootPart solto (os rigs de animação vêm ancorados: ancorado, nenhuma
força o move) e revive sozinho REVIVE_DELAY s depois de morrer (o motor não mata o Humanoid, só
zera o HP: sem isso, o dummy morto não toma mais dano). Nada disso muda o place: só o Play.
]]

local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local DataManager = require(ServerScriptService.EntityData.DataManager)
local StateTable = require(ServerStorage.Modules.Combat.StateTable)

local TAG = "FW_TestTarget"
local DUMMY_FOLDER = "Dummies"
local RIGS = { "Rig", "AshleyRig", "SchemaRig", "VanhousenRig" }
local COMPONENTS = { "Character", "Health", "Status", "Movement" }
local CONFIGS = { Health = { MaxHP = 100 } }
local REVIVE_DELAY = 3

local function register(model: Instance)
	if not model:IsA("Model") or model:GetAttribute("EntityID") then return end -- já é entidade
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return end
	root.Anchored = false

	local entity = DataManager.Create(model, COMPONENTS, CONFIGS)
	if not entity then return end
	entity:Listen({
		Role = StateTable.Enum.Roles.IN,
		Breakpoint = StateTable.Enum.Breakpoints.OnDeath,
		Action = function()
			task.delay(REVIVE_DELAY, function()
				if entity.Active then entity.Revive() end
			end)
		end,
	})
end

for _, model in CollectionService:GetTagged(TAG) do
	register(model)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(register)

local dummies = workspace:FindFirstChild(DUMMY_FOLDER)
if dummies then
	for _, model in dummies:GetChildren() do
		register(model)
	end
end
for _, name in RIGS do
	local rig = workspace:FindFirstChild(name)
	if rig then register(rig) end
end

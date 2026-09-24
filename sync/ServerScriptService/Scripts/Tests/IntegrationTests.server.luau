--[[
Roda uma vez no boot (Studio/PlayEmpty). Cada teste cria e limpa suas
próprias entidades descartáveis. Ferramenta de sprint — não deixe isso
rodando num lugar que vá pra produção real.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local TestHarness = require(script.Parent.TestHarness)
local DataManager = require(ServerScriptService.EntityData.DataManager)
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local BaseSkills = require(ServerStorage.DataBase.SkillDatabase.BaseSkills)

local function makeDummy(cframe: CFrame, components: {string}?, configs: {[string]: any}?, parentEntity: any?)
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = cframe
	root.Anchored = false
	root.Parent = model
	model.PrimaryPart = root
	model.Parent = workspace

	return DataManager.Create(model, components or { "Character", "Health", "Movement" }, configs, parentEntity)
end

local function cleanup(entity: any)
	if entity and entity.Instance then
		entity.Instance:Destroy()
	end
end

task.wait(2) -- deixa o resto do jogo terminar de bootar

TestHarness.Run("Sprint 1 — Block determinístico", function(t)
	local dummy = makeDummy(CFrame.new(0, 10, 0), { "Character", "Health", "Movement", "Status" })

	dummy.ApplyStatus(StateTable.Status.GenericBlock, { Duration = 5, ID = "FirstBlock" })
	task.wait(0.05)
	dummy.ApplyStatus(StateTable.Status.GenericBlock, { Duration = 5, ID = "SecondBlock" })

	local _, owners = dummy.GetActiveTags()
	local blockOwner = owners[StateTable.Enum.Tags.block]

	t.assert(blockOwner ~= nil, "Nenhum dono de block resolvido")
	t.assert(blockOwner.data.ID == "SecondBlock", "Dono resolvido não é o mais recente")

	cleanup(dummy)
end)

TestHarness.Run("Sprint 6 — Floating não confunde com Falling", function(t)
	local dummy = makeDummy(CFrame.new(0, 50, 0), { "Character", "Health", "Movement" })
	dummy.SetMovement()
	task.wait(0.1)

	local stateBeforeForce = dummy.GetAirState()
	t.log("Estado sem Force:", stateBeforeForce)
	t.assert(stateBeforeForce == "Falling" or stateBeforeForce == "Jumping", "Esperava queda livre sem Force ativa")

	local forceId = dummy.AddForce({
		Type = "TestHover", Duration = 2, Hard = true, IgnoreGravity = true,
		Direction = Vector3.zero, Speed = 0, RequiresControl = false,
	})
	task.wait(0.2)

	local stateDuringHover = dummy.GetAirState()
	t.log("Estado hovering:", stateDuringHover)
	t.assert(stateDuringHover == "Floating", "Deveria reportar Floating com Hard force + IgnoreGravity, mesmo sem velocidade")

	dummy.RemoveForce(forceId)
	cleanup(dummy)
end)

TestHarness.Run("Sprint 8/9 — Tether gruda posição + reivindica ownership de servidor", function(t)
	local caster = makeDummy(CFrame.new(0, 5, 0))
	local victim = makeDummy(CFrame.new(10, 5, 0))
	caster.SetMovement()
	victim.SetMovement()

	local forceId = victim.AddForce({
		Type = "TestGrab", Duration = 1, Hard = true, IgnoreGravity = true, RequiresControl = false,
		FollowTarget = function() return caster.GetRoot() end,
		FollowOffset = Vector3.new(0, 0, -3), FollowOffsetIsLocal = true,
		FollowResponsiveness = 20, FollowMaxSpeed = 100,
	})

	task.wait(0.5)

	local expected = caster.GetCFrame():PointToWorldSpace(Vector3.new(0, 0, -3))
	local actual = victim.GetRoot().Position
	local drift = (expected - actual).Magnitude
	t.log("Drift após convergência:", drift, "studs")
	t.assert(drift < 1.5, "Vítima não convergiu — modo Tether não está funcionando")

	local owner = victim.GetRoot():GetNetworkOwner()
	t.assert(owner == nil, "Root da vítima deveria estar sob ownership do SERVIDOR enquanto Hard force ativa")

	victim.RemoveForce(forceId)
	task.wait(0.1)
	cleanup(caster)
	cleanup(victim)
end)

TestHarness.Run("Sprint 10 — Fork de TriggerSet propaga OUT.onHit do minion pro pai", function(t)
	local summoner = makeDummy(CFrame.new(0, 5, 0))
	local heard = false

	local unsubscribe = summoner:Listen({
		Role = StateTable.Enum.Roles.OUT,
		Breakpoint = StateTable.Enum.Breakpoints.onHit,
		Inherit = { Generations = 1 },
		Priority = 0,
		Action = function() heard = true end,
	})

	local minion = makeDummy(CFrame.new(5, 5, 0), nil, nil, summoner)
	minion:Emit(StateTable.Enum.Roles.OUT, StateTable.Enum.Breakpoints.onHit, StateTable.BuildContext(nil, 1))
	task.wait(0.05)

	t.assert(heard, "Listener do summoner não disparou quando o MINION emitiu onHit")

	unsubscribe()
	cleanup(summoner)
	cleanup(minion)
end)

TestHarness.Run("Sprint 11 — ComboWindow marca e consome dentro da janela", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0))

	BaseSkills.ComboWindow.Mark(dummy, "TestMarker", 0.3, { Foo = "bar" })
	local immediate = BaseSkills.ComboWindow.Consume(dummy, "TestMarker")
	t.assert(immediate and immediate.Foo == "bar", "Consume imediato deveria trazer o payload")

	BaseSkills.ComboWindow.Mark(dummy, "TestMarker", 0.1, { Foo = "baz" })
	task.wait(0.3)
	local expired = BaseSkills.ComboWindow.Consume(dummy, "TestMarker")
	t.assert(expired == nil, "Consume após expirar deveria vir nil")

	cleanup(dummy)
end)

TestHarness.Run("Sprint 13 — Link espelha movimento, Unlink corta", function(t)
	local primary = makeDummy(CFrame.new(0, 5, 0), { "Character", "Health", "Movement", "Control" })
	local secondary = makeDummy(CFrame.new(3, 5, 0), { "Character", "Health", "Movement", "Control" })
	primary.SetMovement()
	secondary.SetMovement()

	primary.LinkTo(secondary, { MirrorMovement = true })

	local SkillHandler = require(ServerScriptService.Modules.SkillHandler)
	SkillHandler.HandleMovementInput(primary.ID, Vector3.new(1, 0, 0))
	task.wait(0.05)
	t.assert(secondary.GetDirection().Magnitude > 0.5, "Secundário deveria ter recebido a direção espelhada")

	primary.Unlink(secondary)
	SkillHandler.HandleMovementInput(primary.ID, Vector3.new(0, 0, 1))
	task.wait(0.05)
	t.assert(secondary.GetDirection().X > 0.5, "Após Unlink, secundário não deveria mais atualizar")

	cleanup(primary)
	cleanup(secondary)
end)

TestHarness.Run("Sprint 18 — AddComponent dinâmico dispara OnAdded", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), { "Character", "Health", "Movement" })
	dummy:AddComponent(dummy.ComponentKey.AI, {}, true)

	local ranBrain = false
	dummy.SetBrain(function() ranBrain = true end)
	task.wait(0.1)

	t.assert(ranBrain, "Brain nunca rodou — AIComponent.OnAdded não foi chamado no add dinâmico")
	cleanup(dummy)
end)

task.wait(1)
TestHarness.Summary()

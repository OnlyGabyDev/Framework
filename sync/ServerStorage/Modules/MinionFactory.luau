--!strict
--[[
MinionFactory: reduz o boilerplate de "invocar uma entidade descartável"
SEM decidir por você quais componentes ela deve ter — você declara um
Blueprint (Regra 2: reutilizável) numa pasta Blueprints/, a factory só monta
o Model+DataManager.Create com base nele. Mesmo padrão de auto-scan que
SkillDatabase/CharacterDatabase já usam, não invento convenção nova.
NÃO substitui DataManager.Create: se seu caso não encaixa num Blueprint,
chame DataManager.Create direto — sem bloqueio nenhum (Regra 3).
]]

local ServerScriptService = game:GetService("ServerScriptService")
local DataManager = require(ServerScriptService.EntityData.DataManager)

export type Blueprint = {
	Components: {string},
	Configs: {[string]: any}?,
	Model: Instance?,
	BuildModel: ((cframe: CFrame) -> Model)?,
}

local MinionFactory = {}
local Blueprints: {[string]: Blueprint} = {}

local blueprintsFolder = script:FindFirstChild("Blueprints")
if blueprintsFolder then
	for _, moduleScript in ipairs(blueprintsFolder:GetChildren()) do
		if moduleScript:IsA("ModuleScript") then
			local ok, blueprint = pcall(require, moduleScript)
			if ok then
				Blueprints[moduleScript.Name] = blueprint :: Blueprint
			else
				warn("[MinionFactory] Erro carregando blueprint", moduleScript.Name, blueprint)
			end
		end
	end
end

--[[ Registro em runtime, se preferir não usar a pasta Blueprints/. ]]
function MinionFactory.Register(name: string, blueprint: Blueprint)
	Blueprints[name] = blueprint
end

--[[
@param blueprintName - nome do módulo em Blueprints/ (ou registrado via Register)
@param cframe - onde spawnar
@param parentEntity any? - se fornecido, faz Fork de TriggerSet (Sprint 10)
@return EntityCore ou nil
]]
function MinionFactory.Spawn(blueprintName: string, cframe: CFrame, parentEntity: any?): any?
	local blueprint = Blueprints[blueprintName]
	if not blueprint then
		warn("[MinionFactory] Blueprint não registrado:", blueprintName)
		return nil
	end

	local model: Model
	if blueprint.BuildModel then
		model = blueprint.BuildModel(cframe)
	elseif blueprint.Model then
		model = (blueprint.Model :: Instance):Clone() :: Model
		model:PivotTo(cframe)
	else
		warn("[MinionFactory] Blueprint sem Model nem BuildModel:", blueprintName)
		return nil
	end
	model.Parent = workspace

	local components = {}
	for _, name in ipairs(blueprint.Components) do
		components[name] = name
	end

	return DataManager.Create(model, components, blueprint.Configs, parentEntity)
end

return MinionFactory

--!strict
--!native
--!optimize 2

-- HitboxSpawner
-- Cria hitboxes desacopladas de arma: usadas quando a fonte do dano NÃO é uma
-- arma equipada (magias, minions, hitbox de chão, etc). Não decide CastType,
-- Size, Radius nem ativa nada — só monta o objeto. Quem chama configura via
-- hitbox:SetCastData(...) e ativa via hitbox:HitStart(...).

local ShapecastHitbox = require(script.Parent.ShapecastHitbox)
local Settings = require(script.Parent.ShapecastHitbox.Settings)

local HitboxSpawner = {}

local CARRIER_NAME = "_DecoupledHitboxCarrier"

--[[
Monta o RaycastParams padrão de exclusão pra hitboxes desacopladas: exclui o
Instance do caster (se fornecido) e qualquer extra pedido. ÚNICO ponto que
monta esse filtro fora do HitboxWrapper (Regra 1 — não duplique "monta filtro
de exclusão" em mais um lugar com pequenas divergências).
]]
function HitboxSpawner.BuildDefaultFilter(casterEntity: any?, extraExclude: {Instance}?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local filter = {}
	if casterEntity and casterEntity.Instance then
		table.insert(filter, casterEntity.Instance)
	end
	if extraExclude then
		for _, inst in ipairs(extraExclude) do
			table.insert(filter, inst)
		end
	end
	params.FilterDescendantsInstances = filter

	return params
end

--[[
Cria um hitbox desacoplado. `pointOffsets` são CFrames LOCAIS ao carrier — um
Attachment "DmgPoint" por offset, todos se movendo juntos quando você mover o
carrier (ver SetCarrierCFrame). Múltiplos offsets = múltiplos pontos de dano
no MESMO hitbox (ex: 3 pontos ao longo de um leque de espada).

@param casterEntity any? - EntityCore de quem está criando (só pro filtro default; pode ser nil se você passar raycastParamsOverride)
@param cframe CFrame - posição/orientação inicial do carrier, no mundo
@param pointOffsets {CFrame}? - default: { CFrame.identity } (1 ponto na origem do carrier)
@param raycastParamsOverride RaycastParams? - se fornecido, ignora BuildDefaultFilter
@return (Types.Hitbox, Instance) - guarde os dois: precisa do carrier pra mover/limpar depois
]]
function HitboxSpawner.Spawn(casterEntity: any?, cframe: CFrame, pointOffsets: {CFrame}?, raycastParamsOverride: RaycastParams?): (any, Instance)
	pointOffsets = pointOffsets or { CFrame.identity }

	local carrier = Instance.new("Part")
	carrier.Name = CARRIER_NAME
	carrier.Size = Vector3.one
	carrier.Transparency = 1
	carrier.CanCollide = false
	carrier.CanQuery = false
	carrier.CanTouch = false
	carrier.Anchored = true
	carrier.CFrame = cframe

	for _, offset in ipairs(pointOffsets :: {CFrame}) do
		local point = Instance.new("Attachment")
		point.Name = Settings.Tag -- "DmgPoint" — Hitbox:AddSegment identifica por NOME, não CollectionService
		point.CFrame = offset
		point.Parent = carrier
	end

	carrier.Parent = workspace

	local raycastParams = raycastParamsOverride or HitboxSpawner.BuildDefaultFilter(casterEntity)
	local hitbox = ShapecastHitbox.new(carrier, raycastParams)

	return hitbox, carrier
end

--[[
Move o carrier de um hitbox Móvel. Use isso DENTRO de um hitbox:OnUpdate(dt)
(ver HitboxBehaviors) — nunca escreva carrier.CFrame direto de outro lugar,
pra isso continuar sendo o único ponto que move um carrier.
]]
function HitboxSpawner.SetCarrierCFrame(carrier: Instance, cframe: CFrame)
	if carrier and carrier.Parent then
		(carrier :: BasePart).CFrame = cframe
	end
end

--[[
Destrói hitbox E carrier juntos. ShapecastHitbox:Destroy() só desconecta o
PostSimulation dela — NÃO destrói o Instance. Sem chamar isso, o carrier vaza
pra sempre no workspace.
]]
function HitboxSpawner.Cleanup(hitbox: any, carrier: Instance)
	if hitbox and hitbox.Destroy then
		hitbox:Destroy()
	end
	if carrier then
		carrier:Destroy()
	end
end

return HitboxSpawner

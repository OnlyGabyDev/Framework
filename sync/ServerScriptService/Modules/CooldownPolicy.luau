--[[
CooldownPolicy — dono único das regras de cooldown de skill (D13). A skill DECLARA no data; o
motor executa. O CombatComponent guarda os dados (self.Cooldowns) e delega as contas para cá.
Status não passam por aqui (o cooldown deles é o StatusCooldowns do StatusComponent).

	data = {
		cooldown = 1,                 -- obrigatório; 0 é válido (sem cooldown, declarado)
		cooldownPolicy = {            -- opcional; os padrões estão em Enum.CooldownDefaults
			start  = "Cast",          -- Enum.CooldownStart: Cast | End | Manual
			recast = "Restart",       -- Enum.RecastPolicy: Blocked | Free | Restart, ou um número (s)
			                          --   OBRIGATÓRIO quando a skill tem onRecast
			refund = { fizzle = 1 },  -- fração (0..1) devolvida por motivo de fim (Enum.EndReasons)
			charges = 2,              -- cargas: N usos, cada um recarrega em `cooldown` (uma por vez)
			ignoreReduction = false,  -- true = o stat CooldownReduction não vale para esta skill
			maxReduction = 0.8,       -- teto da redução PARA ESTA SKILL (0..1); padrão do jogo em
			                          --   Enum.CooldownDefaults.maxReduction
		},
	}

start
	Cast   — o cooldown começa na ativação, antes do onStart.
	End    — o cooldown começa no fim do runner (canalização, toggle).
	Manual — a skill confirma com self:CommitCooldown() quando o cast de fato acontece. Se o
	         runner terminar sem confirmar, não houve cast: nada é cobrado.
recast (só para skill com onRecast)
	Blocked — espera o cooldown e não o reinicia. Restart — espera e reinicia (cobra de novo;
	com cargas, gasta uma carga). Free — ignora o cooldown. número — intervalo próprio.
refund
	No fim, devolve refund[motivo] × duração. Com cargas, refund 1 devolve a carga inteira.
cargas
	A skill fica disponível enquanto houver carga. Gastar uma carga com a recarga parada inicia a
	recarga; cada recarga que termina devolve uma carga e, se ainda faltar, emenda a próxima.
redução (stat Enum.Stats.CooldownReduction, fração)
	Aplicada quando uma contagem COMEÇA: duração = cooldown × (1 − min(redução, teto)). O teto é
	design de jogo: cada skill declara o seu (maxReduction, 0..1; 1 = sem teto); sem declaração
	vale o padrão declarado em Enum.CooldownDefaults.maxReduction. Mudar o stat não reescala
	contagens em andamento; para isso existe ReduceCooldown (segundos) no CombatComponent.
herança (skill roubada, possessão)
	CooldownPolicy.Transfer(de, para, nomeDaSkill, "Copy" | "Move") copia o estado (tempo restante
	e cargas) de uma entidade para outra; Move também libera a de origem.

Formato de uma entrada do armazenamento (dono deste formato, regra 17):
	Cooldowns[nome] = {
		endAt: number,        -- tick() em que a contagem corrente termina (0 = nenhuma)
		duration: number,     -- duração efetiva da contagem corrente
		charges: number?,     -- cargas disponíveis (nil = skill sem cargas)
		maxCharges: number?,
	}
]]

local ServerStorage = game:GetService("ServerStorage")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)

local Enum = StateTable.Enum
local START = Enum.CooldownStart
local RECAST = Enum.RecastPolicy
local DEFAULTS = Enum.CooldownDefaults

local CooldownPolicy = {}

local resolved = setmetatable({}, { __mode = "k" }) -- [data] = policy (dado estático da skill)
local warned = setmetatable({}, { __mode = "k" })   -- [tabela] = true: aviso uma vez

local function now()
	return tick()
end

local function isEnumValue(enumTable, value)
	for _, v in enumTable do
		if v == value then return true end
	end
	return false
end

--=============================================================================
--  POLÍTICA DECLARADA
--=============================================================================

--[[
Lê e valida a política declarada, sem efeito colateral.
@return policy { cooldown, start, recast, refund, charges?, ignoreReduction }, issues {string}
]]
function CooldownPolicy.Validate(data, callbacks)
	local issues = {}
	local declared = data.cooldownPolicy or {}

	local cooldown = data.cooldown
	if type(cooldown) ~= "number" or cooldown < 0 then
		table.insert(issues, "cooldown ausente ou inválido (" .. tostring(cooldown) .. "); declare um número >= 0, usando 0")
		cooldown = 0
	end

	local start = declared.start or DEFAULTS.start
	if not isEnumValue(START, start) then
		table.insert(issues, "cooldownPolicy.start inválido (" .. tostring(start) .. "), usando " .. DEFAULTS.start)
		start = DEFAULTS.start
	end

	local hasRecast = callbacks ~= nil and rawget(callbacks, "onRecast") ~= nil
	local recast = declared.recast
	if recast == nil then
		if hasRecast then
			table.insert(issues, "skill com onRecast precisa declarar cooldownPolicy.recast; usando "
				.. DEFAULTS.recastLegacy .. " (o comportamento antigo)")
		end
		recast = DEFAULTS.recastLegacy
	elseif type(recast) == "number" then
		if recast < 0 then
			table.insert(issues, "cooldownPolicy.recast numérico precisa ser >= 0, usando 0")
			recast = 0
		end
	elseif not isEnumValue(RECAST, recast) then
		table.insert(issues, "cooldownPolicy.recast inválido (" .. tostring(recast) .. "), usando " .. DEFAULTS.recastLegacy)
		recast = DEFAULTS.recastLegacy
	end

	local refund = table.clone(DEFAULTS.refund)
	for reason, fraction in declared.refund or {} do
		if not isEnumValue(Enum.EndReasons, reason) then
			table.insert(issues, "refund com motivo desconhecido: " .. tostring(reason))
		elseif type(fraction) ~= "number" or fraction < 0 or fraction > 1 then
			table.insert(issues, "refund." .. tostring(reason) .. " precisa estar entre 0 e 1")
		else
			refund[reason] = fraction
		end
	end

	local maxReduction = declared.maxReduction
	if maxReduction == nil then
		maxReduction = DEFAULTS.maxReduction
	elseif type(maxReduction) ~= "number" or maxReduction < 0 or maxReduction > 1 then
		table.insert(issues, "cooldownPolicy.maxReduction precisa estar entre 0 e 1, usando o padrão "
			.. tostring(DEFAULTS.maxReduction))
		maxReduction = DEFAULTS.maxReduction
	end

	local charges = declared.charges
	if charges ~= nil and (type(charges) ~= "number" or charges < 1 or charges % 1 ~= 0) then
		table.insert(issues, "cooldownPolicy.charges precisa ser um inteiro >= 1; ignorando")
		charges = nil
	end

	return {
		cooldown = cooldown,
		start = start,
		recast = recast,
		refund = refund,
		charges = charges,
		ignoreReduction = declared.ignoreReduction == true,
		maxReduction = maxReduction,
	}, issues
end

--[[ Política da skill, validada uma vez (avisa uma vez se houver problema) ]]
function CooldownPolicy.Resolve(data, callbacks)
	local policy = resolved[data]
	if policy then return policy end

	local issues
	policy, issues = CooldownPolicy.Validate(data, callbacks)
	resolved[data] = policy
	if #issues > 0 and not warned[data] then
		warned[data] = true
		warn("[CooldownPolicy] " .. tostring(data.name) .. ": " .. table.concat(issues, "; "))
	end
	return policy
end

local function policyOf(runner)
	return CooldownPolicy.Resolve(runner.data, runner.callbacks)
end

--[[
Duração efetiva de uma contagem que começa agora: cooldown × (1 − CooldownReduction), com o
stat lido do AttributesComponent (dependência opcional, regra 16) e limitado ao teto DA SKILL.
]]
function CooldownPolicy.EffectiveDuration(entity, policy): number
	if policy.ignoreReduction or not entity:HasComponent(entity.ComponentKey.Attributes) then
		return policy.cooldown
	end
	local reduction = entity.GetStat(Enum.Stats.CooldownReduction, Enum.StatDefaults.CooldownReduction)
	reduction = math.clamp(reduction, 0, policy.maxReduction)
	return policy.cooldown * (1 - reduction)
end

--=============================================================================
--  ARMAZENAMENTO (funções puras sobre CombatComponent.Cooldowns)
--=============================================================================

-- Recarga preguiçosa: devolve as cargas cujas recargas já terminaram e emenda a próxima
local function settle(entry, t)
	if entry.charges == nil then return end
	while entry.charges < entry.maxCharges and entry.endAt > 0 and entry.endAt <= t do
		entry.charges += 1
		if entry.charges < entry.maxCharges then
			entry.endAt += entry.duration
		else
			entry.endAt = 0
		end
	end
end

function CooldownPolicy.StoreIsReady(store, name): boolean
	local entry = store[name]
	if not entry then return true end
	local t = now()
	settle(entry, t)
	if entry.charges ~= nil then
		return entry.charges > 0
	end
	return entry.endAt <= t
end

-- Segundos até poder usar de novo (0 = pronta; com cargas, 0 enquanto houver carga)
function CooldownPolicy.StoreRemaining(store, name): number
	local entry = store[name]
	if not entry then return 0 end
	local t = now()
	settle(entry, t)
	if entry.charges ~= nil and entry.charges > 0 then return 0 end
	return math.max(0, entry.endAt - t)
end

-- Inicia uma contagem (ou gasta uma carga) de `duration` segundos
function CooldownPolicy.StoreStart(store, name, duration, maxCharges)
	local t = now()
	if maxCharges then
		local entry = store[name]
		if not entry or entry.charges == nil or entry.maxCharges ~= maxCharges then
			entry = { endAt = 0, duration = duration, charges = maxCharges, maxCharges = maxCharges }
			store[name] = entry
		end
		settle(entry, t)
		entry.charges = math.max(0, entry.charges - 1)
		if entry.endAt <= t then -- recarga parada: começa agora
			entry.duration = duration
			entry.endAt = t + duration
		end
		return
	end
	if duration <= 0 then
		store[name] = nil
		return
	end
	store[name] = { endAt = t + duration, duration = duration }
end

-- Define o tempo restante da contagem corrente (sem cargas: o cooldown; com cargas: a recarga)
function CooldownPolicy.StoreSetRemaining(store, name, seconds)
	local entry = store[name]
	local t = now()
	if entry and entry.charges ~= nil then
		settle(entry, t)
		if entry.charges < entry.maxCharges then
			entry.endAt = t + math.max(0, seconds)
			settle(entry, t)
		end
		return
	end
	if seconds <= 0 then
		store[name] = nil
		return
	end
	store[name] = { endAt = t + seconds, duration = entry and entry.duration or seconds }
end

-- Encurta a contagem corrente em `seconds` (reduções pontuais: on-hit, on-kill)
function CooldownPolicy.StoreReduce(store, name, seconds)
	local entry = store[name]
	if not entry or seconds <= 0 then return end
	local t = now()
	settle(entry, t)
	if entry.endAt <= 0 then return end
	entry.endAt -= seconds
	if entry.charges ~= nil then
		settle(entry, t)
	elseif entry.endAt <= t then
		store[name] = nil
	end
end

-- Devolve uma carga (sem cargas: zera o cooldown)
function CooldownPolicy.StoreGrant(store, name)
	local entry = store[name]
	if not entry then return end
	if entry.charges == nil then
		store[name] = nil
		return
	end
	settle(entry, now())
	entry.charges = math.min(entry.maxCharges, entry.charges + 1)
	if entry.charges >= entry.maxCharges then entry.endAt = 0 end
end

-- Pronta de novo (com cargas: todas)
function CooldownPolicy.StoreReset(store, name)
	store[name] = nil
end

function CooldownPolicy.StoreCharges(store, name): (number?, number?)
	local entry = store[name]
	if not entry or entry.charges == nil then return nil, nil end
	settle(entry, now())
	return entry.charges, entry.maxCharges
end

-- Estado em tempo RELATIVO (segundos restantes), para copiar entre entidades
function CooldownPolicy.StoreExport(store, name)
	local entry = store[name]
	if not entry then return nil end
	local t = now()
	settle(entry, t)
	return {
		remaining = math.max(0, entry.endAt - t),
		duration = entry.duration,
		charges = entry.charges,
		maxCharges = entry.maxCharges,
	}
end

function CooldownPolicy.StoreImport(store, name, snapshot)
	if not snapshot then
		store[name] = nil
		return
	end
	local t = now()
	store[name] = {
		endAt = if snapshot.remaining > 0 then t + snapshot.remaining else 0,
		duration = snapshot.duration,
		charges = snapshot.charges,
		maxCharges = snapshot.maxCharges,
	}
	if snapshot.charges == nil and snapshot.remaining <= 0 then
		store[name] = nil
	end
end

--[[
Herança de cooldown (skill roubada, possessão): copia o estado da skill de `from` para `to`.
mode = "Copy" (padrão): as duas ficam com o mesmo estado. "Move": `from` fica pronta.
@return copiou BOOLEAN
]]
function CooldownPolicy.Transfer(from, to, skillName, mode)
	local combat = from.ComponentKey.Combat
	if not from:HasComponent(combat) or not to:HasComponent(to.ComponentKey.Combat) then
		warn("[CooldownPolicy] Transfer exige CombatComponent nas duas entidades:", skillName)
		return false
	end
	to.ImportCooldown(skillName, from.ExportCooldown(skillName))
	if mode == "Move" then
		from.ResetCooldown(skillName)
	end
	return true
end

--=============================================================================
--  CICLO DE VIDA DO CAST (chamado pelo SkillHandler e pelo SkillRunner)
--=============================================================================

local function charge(entity, runner, policy, duration)
	entity.StartCooldown(runner.skillName, duration, policy.charges)
end

--[[ Chamado pelo SkillHandler logo antes do runner:start() de um cast novo ]]
function CooldownPolicy.OnActivate(entity, runner)
	local policy = policyOf(runner)
	local duration = CooldownPolicy.EffectiveDuration(entity, policy)
	runner._cooldownState = { committed = false, duration = duration }
	if policy.start == START.Cast then
		charge(entity, runner, policy, duration)
		runner._cooldownState.committed = true
	end
	if type(policy.recast) == "number" then
		runner._cooldownState.recastReadyAt = os.clock() + policy.recast
	end
end

--[[ O toque que viraria recast pode rodar agora? ]]
function CooldownPolicy.CanRecast(entity, runner): boolean
	local policy = policyOf(runner)
	local recast = policy.recast
	if recast == RECAST.Free then
		return true
	elseif type(recast) == "number" then
		local state = runner._cooldownState
		return state == nil or state.recastReadyAt == nil or os.clock() >= state.recastReadyAt
	end
	return not entity.HasCooldown(runner.skillName) -- Blocked e Restart
end

--[[ Depois do onRecast: Restart cobra de novo; o intervalo numérico recomeça ]]
function CooldownPolicy.OnRecast(entity, runner)
	local policy = policyOf(runner)
	local state = runner._cooldownState
	if policy.recast == RECAST.Restart then
		charge(entity, runner, policy, CooldownPolicy.EffectiveDuration(entity, policy))
		if state then state.committed = true end
	elseif type(policy.recast) == "number" and state then
		state.recastReadyAt = os.clock() + policy.recast
	end
end

--[[
self:CommitCooldown() da skill. Só vale com start = Manual, uma vez por runner.
@return confirmou BOOLEAN
]]
function CooldownPolicy.Commit(runner): boolean
	local state = runner._cooldownState
	local policy = policyOf(runner)
	if policy.start ~= START.Manual then
		if not warned[runner.callbacks] then
			warned[runner.callbacks] = true
			warn("[CooldownPolicy] " .. tostring(runner.skillName) .. ": CommitCooldown só vale com cooldownPolicy.start = Manual")
		end
		return false
	end
	if not state or state.committed or runner:IsEnded() then return false end
	charge(runner.Entity, runner, policy, state.duration)
	state.committed = true
	return true
end

--[[ Chamado pelo SkillRunner no fim de um runner que passou pelo OnActivate ]]
function CooldownPolicy.OnEnd(runner, reason)
	local state = runner._cooldownState
	local entity = runner.Entity
	if not state or not entity or not entity:HasComponent(entity.ComponentKey.Combat) then return end
	runner._cooldownState = nil
	local policy = policyOf(runner)
	local fraction = policy.refund[reason] or 0
	local name = runner.skillName

	if policy.start == START.End then
		if fraction < 1 then
			charge(entity, runner, policy, state.duration * (1 - fraction))
		end
		return
	end
	if not state.committed or fraction <= 0 then return end

	if fraction >= 1 then
		entity.GrantCooldownCharge(name) -- com cargas: a carga volta; sem cargas: pronta
	else
		entity.ReduceCooldown(name, fraction * state.duration)
	end
end

return CooldownPolicy

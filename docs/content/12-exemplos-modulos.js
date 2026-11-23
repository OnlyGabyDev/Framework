/*
  Exemplos de uso: módulos de combate, input, física/rede e cliente.
  Estilo e requires: ver o topo de 09-exemplos-nucleo.js. Requires dos módulos usados aqui:
  AreaEffect = require(game.ServerStorage.Modules.Combat.AreaEffect)
  Presets = require(game.ServerStorage.Modules.Combat.Hitbox.HitboxPresets)
  HitboxSpawner = require(game.ServerStorage.Modules.Combat.Hitbox.HitboxSpawner)
  Behaviors = require(game.ServerStorage.Modules.Combat.Hitbox.HitboxBehaviors)
*/
(function () {
  var X = DOCS.example;

  // ================================================================ StateTable
  X("api.StateTable.Relation", {
    code: `
local rel = StateTable.Relation(self.Entity, alvo)
if rel == Enum.Relations.Ally then
    alvo.Heal(20, { Source = self.Runner })
elseif rel == Enum.Relations.Enemy then
    self:Damage(alvo, 20)
end
-- Self e Neutral: nada
`,
    desc: `O código acima faz uma skill curar aliados e ferir inimigos. A relação é <code>Self</code> (a mesma entidade), <code>Ally</code> (mesmo time), <code>Enemy</code> (times diferentes) ou <code>Neutral</code> (um dos dois sem o componente Affiliation, como um boneco de treino).`,
  });

  X("api.StateTable.CanAffect", [
    {
      t: "área manual",
      code: `
onStart = function(self)
    self.atingidos = {}
    local centro = self.Entity.GetPosition()
    for _, part in workspace:GetPartBoundsInRadius(centro, 12) do
        local e = DataManager.GetEntityFromInstance(part)
        if e and not self.atingidos[e] and StateTable.CanAffect(self, e) then
            self.atingidos[e] = true
            self:Damage(e, 20)
        end
    end
end,
`,
      desc: `O código acima é uma explosão que fere quem a skill pode afetar num raio de 12 studs (a tabela <code>self.atingidos</code> faz cada entidade levar o dano uma vez só, já que várias peças do mesmo corpo caem no raio). Com o <code>self</code> da skill, vale o <code>data.affects</code> dela sobre <code>Enum.AffectsDefaults</code>: por padrão, inimigos e neutros sim, aliados e a própria entidade não.`,
    },
    {
      t: "regra explícita",
      code: `
-- aura que afeta só aliados, sem depender do data da skill
if StateTable.CanAffect(self.Entity, e, { Ally = true, Self = true }) then
    e.Heal(5)
end
`,
      desc: `O código acima passa a regra de alvo direto no 3º argumento e usa a entidade como fonte (não o runner). Com <code>nil</code> como fonte (ambiente), tudo é afetado.`,
    },
  ]);

  X("api.StateTable.AffectsFilter", {
    code: `
onStart = function(self)
    local zona = AreaEffect.new(function() return self.Entity.GetCFrame() end, "Sphere", 10)
    zona:SetFilter(StateTable.AffectsFilter(self))
    zona:OnStay(function(e) self:Damage(e, 2) end)
    zona:Start()
    self:Own(function() zona:Stop() end)
end,
`,
    desc: `O código acima cria uma aura de dano em volta de quem casta que só considera quem a skill pode afetar: o filtro pronto aplica o <code>data.affects</code> da skill a cada entidade que a zona encontra, então aliados nem chegam no <code>OnStay</code>.`,
  });

  X("api.StateTable.EffectOwner", {
    code: `
-- dentro do onStep de um veneno, que roda na vítima
onStep = function(self, dt)
    local dono = StateTable.EffectOwner(self.Runner)
    if dono and dono.Active then
        print("o veneno é de", dono.ID, "e roda em", self.Entity.ID)
    end
end,
`,
    desc: `O código acima descobre quem aplicou o veneno. O status roda no portador (<code>self.Entity</code>), mas o dono do efeito é quem o causou: a função sobe pelo <code>Source</code> dos status até um runner de skill. É esse dono que recebe <span class="badge out">OUT</span> <code>OnDamage</code>, <code>OnDeath</code> e <code>OnHeal</code>. Devolve <code>nil</code> se o dono já saiu do jogo.`,
  });

  X("api.StateTable.OwnerToken", {
    code: `
local dono = StateTable.OwnerToken(alvo, "Marca")
alvo:Listen({ Role = Enum.Roles.IN, Breakpoint = Enum.Breakpoints.PreDamage,
    Owner = dono, Action = function(ctx) ctx.damage *= 1.2 end })

-- mais tarde, só a marca deste alvo sai
alvo:UnsubscribeByOwner(StateTable.OwnerToken(alvo, "Marca"))
`,
    desc: `O código acima inscreve e depois remove a "Marca" de um alvo. A mesma entidade com a mesma tag dá sempre o mesmo token, então não é preciso guardá-lo. Um Owner em string (<code>"Marca"</code>) seria o mesmo para todas as entidades; o token é por entidade.`,
  });

  X("api.StateTable.HasTrait", {
    code: `
self:Listen({
    Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.onStart,
    Action = function(ctx)
        local r = ctx.sourceRunner
        if r and StateTable.HasTrait(r.skill.data, Enum.Traits.Ultimate) then
            print("começou uma Ultimate")
        end
    end,
})
`,
    desc: `O código acima reage ao início de qualquer skill com a trait Ultimate. <code>HasTrait</code> olha o <code>traits</code> de um <code>data</code> de skill ou status; <code>nil</code> ou sem traits devolve <code>false</code>.`,
  });

  X("api.StateTable.ResolveRunner", {
    code: `
-- guardar quem prendeu o alvo, comparando por runner (self e runner são objetos diferentes)
local donoDoGrab = StateTable.ResolveRunner(self)
if alvo.grabbedBy == donoDoGrab then return end
alvo.grabbedBy = donoDoGrab
`,
    desc: `O código acima normaliza o <code>self</code> de uma skill para o runner dela antes de comparar. Dentro da skill, <code>self</code> é a instância isolada e <code>self.Runner</code> é o runner; funções que guardam ou comparam "quem fez" devem usar sempre o runner.`,
  });

  X("api.StateTable.IsDead", {
    code: `
local vivos = {}
for _, e in candidatos do
    if not StateTable.IsDead(e) then table.insert(vivos, e) end
end
`,
    desc: `O código acima filtra as entidades vivas. Diferente de <code>e.IsAlive()</code>, <code>IsDead</code> funciona em qualquer entidade: sem o componente Health, ela nunca está morta (uma torre indestrutível, uma carta sem vida).`,
  });

  X("api.StateTable.MitigateDamage", {
    code: `
-- prever o dano que um golpe de 100 faria no alvo, para mostrar na mira
local previsto = StateTable.MitigateDamage(100, alvo.GetStat, {})
print(previsto)   -- 50 com Defense 100 e Armor 0
`,
    desc: `O código acima calcula o dano depois das proteções de stat do alvo, na ordem de <code>Enum.DamageMitigation</code>: Defense multiplicativa (<code>dano × 100 / (100 + Defense)</code>) e Armor subtrativa. Traits como <code>TrueDamage</code> na lista furam as proteções. O <code>TakeDamage</code> já faz esta conta; chamar à mão serve para prever.`,
  });

  X("api.StateTable.ResolveBlock", {
    code: `
local muralha = { name = "Muralha", block = { mode = Enum.BlockModes.Percent, value = 0.6 } }
print(StateTable.ResolveBlock(muralha, { damage = 50 }))   -- 20
print(StateTable.ResolveBlock({ name = "Total", block = { mode = Enum.BlockModes.Full } },
    { damage = 50 }))                                        -- 0
`,
    desc: `O código acima calcula o resultado de dois bloqueios declarados sem <code>onTrigger</code>: 60% de redução e bloqueio total. Contra um status (contexto com <code>incomingStatus</code>), o modo Full devolve <code>true</code> (status barrado). Um <code>block</code> mal declarado avisa uma vez e não bloqueia.`,
  });

  X("api.StateTable.ResolveEffect", {
    code: `
data = {
    effects = {
        StateTable.Status.Bleed,                                    -- regra da skill
        { status = StateTable.Status.Slow, onBlocked = true },      -- vale até em golpe bloqueado
    },
    effectPolicy = { onZeroDamage = false },                        -- golpe de 0 não aplica
},
-- por dentro, para cada efeito:
-- local status, onBlocked, onZeroDamage = StateTable.ResolveEffect(entrada, data)
`,
    desc: `O código acima declara dois efeitos on-hit com regras diferentes. Para cada um, a regra vem do próprio efeito, depois do <code>effectPolicy</code> da skill e por fim de <code>Enum.EffectDefaults</code>. O motor chama <code>ResolveEffect</code> no <code>TakeDamage</code>; o jogo só declara.`,
  });

  X("api.StateTable.RunInChain", {
    code: `
-- uma bomba que explode quem ela matar (reação em cadeia)
local function explodir(origem)
    for _, e in vizinhos(origem, 10) do
        e.TakeDamage(40)
    end
end

local ok, motivo = StateTable.RunInChain("[Bomba] explodir", origem.ID, explodir, origem)
if not ok then print("explosão adiada ou recusada:", motivo) end
`,
    desc: `O código acima roda uma explosão como um elo da cadeia síncrona. Se a cadeia estiver funda demais (acima de <code>Enum.MAX_RECURSION</code>), a ação vai para uma fila e roda no próximo frame, em vez de estourar a pilha do servidor: quem chama recebe <code>false, Enum.ChainOutcomes.Deferred</code>. Um erro dentro vira warn e <code>false, Error</code>. Dano e status do motor já passam por aqui; use para ações do jogo que geram outras em cascata.`,
  });

  X("api.StateTable.RunInChainReserving", {
    code: `
-- uma ação que, por dentro, chama outra ação da cadeia (dano e depois status)
StateTable.RunInChainReserving(2, "[Golpe] dano+marca", alvo.ID, function()
    alvo.TakeDamage(10)
    alvo.ApplyStatus(marca, 3)
end)
`,
    desc: `O código acima reserva dois níveis da cadeia para uma ação composta, garantindo que o dano e o status rodem juntos na mesma pilha (ou sejam adiados juntos). É o que o <code>ApplyDamage</code> faz para o <span class="badge out">OUT</span> <code>onHit</code> e o <code>TakeDamage</code> do alvo.`,
  });

  X("api.StateTable.GetDeferredCount", {
    code: `
game:GetService("RunService").Heartbeat:Connect(function()
    local n = StateTable.GetDeferredCount()
    if n > 100 then warn("cadeia longa na fila:", n) end
end)
`,
    desc: `O código acima vigia a fila de ações adiadas da cadeia. Em jogo normal ela fica em 0; um número alto e crescente indica uma reação em cadeia sem fim (que o motor corta em <code>Enum.ChainLimits.maxDeferrals</code> gerações).`,
  });

  X("api.StateTable.BuildContext", {
    code: `
-- dano "à mão", com as traits e o dono de uma skill, mas sem passar pelo atacante
local ctx = StateTable.BuildContext(self.Runner, 25)
table.insert(ctx.traits, "Explosao")
alvo.TakeDamage(ctx)
`,
    desc: `O código acima monta o HitContext de um golpe a partir do runner (traits e efeitos do <code>data</code>, dono do efeito, direção do input, cadeia) e o entrega pronto ao alvo. O <code>TakeDamage</code> aceita um contexto no lugar do número. Para o caminho completo do atacante (DamageMult, <code>OUT.onHit</code>), use <code>self:Damage</code>.`,
  });

  X("api.StateTable.ResolveDeathPolicy", {
    code: `
-- num componente novo: a regra "morto não recebe" lida uma vez, no new()
function Escudo.new(entity, config)
    local self = setmetatable({ Entity = entity }, Escudo)
    self.recusaNaMorte = StateTable.ResolveDeathPolicy(config, "RefuseStatusOnDeath")
    return self
end
`,
    desc: `O código acima lê uma regra de morte do motor com override por config: vale o valor do config do componente, ou o padrão de <code>Enum.DeathDefaults</code>. Uma chave que não existe nos padrões dá erro, de propósito.`,
  });

  X("api.StateTable.BuildEffect", {
    code: `
-- um bloqueio que reflete metade do dano, sem criar módulo novo
local Refletor = StateTable:BuildEffect(StateTable.Status.GenericBlock, "onTrigger", function(self, hitCtx)
    if hitCtx.ownerEntity then hitCtx.ownerEntity.TakeDamage(hitCtx.damage * 0.5) end
    return 0
end)

entity.ApplyStatus(Refletor, { Duration = 2 })
`,
    desc: `O código acima cria uma variação do GenericBlock com um <code>onTrigger</code> próprio: bloqueia tudo e devolve metade do dano a quem bateu. O status original não muda (os callbacks são clonados). Note os dois-pontos: <code>BuildEffect</code> é método do StateTable.`,
  });

  // ================================================================ TriggerSet / TraitQuery
  X("api.TriggerSet.Subscribe", {
    code: `
local TriggerSet = require(game.ServerStorage.Modules.Combat.TriggerSet)

local eventos = TriggerSet.new()
local sair = eventos:Subscribe({
    Role = "OUT", Breakpoint = "OnCardPlayed", Priority = 10,
    Action = function(ctx) print("carta jogada", ctx.carta) end,
})
`,
    desc: `O código acima cria um TriggerSet solto (um pub/sub próprio, fora de entidade) e inscreve uma reação. A inscrição entra ordenada por <code>Priority</code> (maior roda antes). O jogo quase sempre usa o TriggerSet pela entidade (<code>entity:Listen</code>); um solto serve para sistemas sem entidade.`,
  });

  X("api.TriggerSet.Unsubscribe", {
    code: `
local sub = { Role = "OUT", Breakpoint = "OnCardPlayed", Action = reagir }
eventos:Subscribe(sub)
-- ...
eventos:Unsubscribe(sub)
`,
    desc: `O código acima tira uma inscrição pela própria tabela dela. É o mesmo que chamar a função devolvida pelo <code>Subscribe</code>.`,
  });

  X("api.TriggerSet.UnsubscribeByOwner", {
    code: `
eventos:Subscribe({ Role = "OUT", Breakpoint = "A", Owner = carta, Action = fa })
eventos:Subscribe({ Role = "OUT", Breakpoint = "B", Owner = carta, Action = fb })

eventos:UnsubscribeByOwner(carta)   -- as duas saem
`,
    desc: `O código acima remove de uma vez todas as inscrições de um dono, em qualquer breakpoint. Desinscrever durante um Emit é seguro: quem foi removido não roda mais nesse Emit.`,
  });

  X("api.TriggerSet.HasAny", {
    code: `
if eventos:HasAny("OUT", "OnCardPlayed") then
    eventos:Emit("OUT", "OnCardPlayed", { traits = {}, carta = carta })
end
`,
    desc: `O código acima só monta e emite o contexto se houver inscrição no canal.`,
  });

  X("api.TriggerSet.Emit", {
    code: `
eventos:Emit("OUT", "OnCardPlayed", { traits = { "Feitiço" }, carta = carta }, jogador)
`,
    desc: `O código acima dispara o canal: cada inscrição viva (TTD não expirado, Query casando com <code>traits</code>, Limit não esgotado) roda com <code>(ctx, jogador)</code>. As Actions recebem o mesmo objeto de contexto, então o que uma muda a seguinte vê. Um erro numa Action vira warn e as outras seguem.`,
  });

  X("api.TriggerSet.Fork", {
    code: `
-- o que o DataManager faz ao criar uma entidade com pai:
local filho = paiTriggerSet:Fork()
-- o filho nasce com as inscrições do pai que têm Inherit = { Generations = n > 0 },
-- agora com Generations = n - 1
`,
    desc: `O código acima mostra a herança de reações: o Fork copia só as inscrições marcadas com <code>Inherit</code>, uma geração a menos. É por isso que um minion invocado com pai herda o on-hit do invocador. O jogo usa pelo 4º argumento do <code>DataManager.Create</code> ou do <code>MinionFactory.Spawn</code>.`,
  });

  X("api.TraitQuery.Match", {
    code: `
local TraitQuery = require(game.ServerStorage.Modules.Combat.TraitQuery)

local q = { All = { "Melee" }, None = { Enum.Traits.DOT } }
print(TraitQuery.Match(q, { "Melee", "Fogo" }))                 -- true
print(TraitQuery.Match(q, { "Melee", Enum.Traits.DOT }))        -- false
print(TraitQuery.Match(nil, {}))                                -- true
`,
    desc: `O código acima testa uma query contra listas de traits: precisa ter todas as de <code>All</code>, nenhuma de <code>None</code> e, se houver <code>Any</code>, pelo menos uma. É a mesma conta do <code>Query</code> das inscrições; sem query, sempre casa.`,
  });

  // ================================================================ AreaEffect
  X("api.AreaEffect.new", [
    {
      t: "zona parada",
      code: `
local poca = workspace.PocaDeVeneno
local zona = AreaEffect.new(function() return poca.CFrame end, "Box", poca.Size, 5)
zona:OnEnter(function(e) e.ApplyStatus(veneno, { Duration = 3 }) end)
zona:Start()
`,
      desc: `O código acima cria uma zona do tamanho de uma peça, consultada 5 vezes por segundo, que envenena quem entra. A forma é consultada no mundo a cada poll (não usa <code>.Touched</code>, que falha com objetos rápidos).`,
    },
    {
      t: "zona que acompanha a entidade",
      code: `
local aura = AreaEffect.new(function() return chefe.GetCFrame() end, "Sphere", 15)
`,
      desc: `O código acima cria uma esfera de raio 15 que anda com o chefe: a função de CFrame é lida a cada poll. A zona nasce parada; chame <code>:Start()</code>. Cada zona tem um <code>zona.ID</code> único (útil como origem de modificador e Key de Force).`,
    },
  ]);

  X("api.AreaEffect.OnEnter", {
    code: `
zona:OnEnter(function(e, z)
    e.AddModifier(Enum.Stats.Speed, z.ID, Enum.ModifierType.MultPercent, 0.5)
end):OnExit(function(e, z)
    e.RemoveModifier(Enum.Stats.Speed, z.ID)
end)
`,
    desc: `O código acima deixa lento quem entra na zona e devolve a velocidade na saída. Os métodos de callback devolvem a zona, então podem ser encadeados. Cada callback roda numa thread própria.`,
  });

  X("api.AreaEffect.OnStay", {
    code: `
zona:OnStay(function(e)
    e.TakeDamage(2, self.Runner)   -- 2 por poll: com pollRate 10, 20 por segundo
end)
`,
    desc: `O código acima causa dano contínuo a quem fica dentro. O OnStay roda a cada poll em que a entidade continua dentro (não no poll em que ela entra, que é do OnEnter), então o dano por segundo depende do <code>pollRate</code>.`,
  });

  X("api.AreaEffect.OnExit", {
    code: `
zona:OnExit(function(e)
    if e.Active then e.RemoveStatus("Veneno") end
end)
`,
    desc: `O código acima tira o veneno de quem sai da zona. O OnExit também roda para todos que estavam dentro quando a zona para (<code>:Stop()</code>), então a limpeza fica num lugar só. O <code>e.Active</code> cobre a entidade que saiu do jogo dentro da zona.`,
  });

  X("api.AreaEffect.SetFilter", {
    code: `
-- só players
zona:SetFilter(function(e) return e:IsPlayer() end)
-- ou a regra de alvo da skill
zona:SetFilter(StateTable.AffectsFilter(self))
`,
    desc: `O código acima restringe quem a zona considera. Quem não passa no filtro nunca dispara OnEnter, OnStay nem OnExit. Sem filtro (<code>nil</code>), toda entidade conta.`,
  });

  X("api.AreaEffect.Start", {
    code: `
onStart = function(self)
    self.zona = AreaEffect.new(function() return self.Entity.GetCFrame() end, "Sphere", 8)
    self.zona:OnStay(function(e) self:Damage(e, 1) end)
    self.zona:Start()
    self:Own(function() self.zona:Stop() end)
end,
`,
    desc: `O código acima liga a zona no início da skill e entrega o <code>Stop</code> ao runner, para ela não sobreviver ao fim da skill. Chamar <code>Start</code> numa zona já ligada não faz nada.`,
  });

  X("api.AreaEffect.Stop", {
    code: `
task.delay(10, function()
    zona:Stop()   -- quem estava dentro recebe o OnExit
end)
`,
    desc: `O código acima desliga a zona depois de 10 segundos. Quem estava dentro sai pelo OnExit, o que desfaz modificadores e Forces ligados na entrada. A zona pode ser ligada de novo com <code>Start</code>.`,
  });

  // ================================================================ AreaBehaviors
  X("api.AreaBehaviors.BindDirectionalForce", {
    code: `
local AreaBehaviors = require(game.ServerStorage.Modules.Combat.AreaBehaviors)
local ventilador = workspace.Ventilador

local zona = AreaEffect.new(function() return ventilador.CFrame * CFrame.new(0, 0, -10) end,
    "Box", Vector3.new(8, 8, 20))
AreaBehaviors.BindDirectionalForce(zona, function() return ventilador.CFrame.LookVector end, 35, "Vento")
zona:Start()
`,
    desc: `O código acima é um ventilador que empurra para a frente quem estiver no corredor de ar à frente dele, mesmo se o ventilador girar (a direção é uma função). A força vale da entrada até a saída: não sobra empurrão depois da borda, nem depois de um dash para fora. Por padrão é Soft (soma com a caminhada) e externa (empurra mesmo quem está em Stun).`,
  });

  X("api.AreaBehaviors.DirectionalForce", {
    code: `
-- rajada única, sem zona: empurra o alvo por 0,5 s
AreaBehaviors.DirectionalForce(alvo, Vector3.new(0, 1, 0), 60, "Geiser", { Duration = 0.5 })
`,
    desc: `O código acima lança o alvo para cima por meio segundo, como um gêiser. Chamada de novo com a mesma <code>Key</code> (padrão: o tipo + a zona), renova a mesma Force em vez de somar. Entidade sem Movement é ignorada (devolve <code>nil</code>).`,
  });

  // ================================================================ Hitbox solta
  X("api.HitboxSpawner.Spawn", {
    code: `
onStart = function(self)
    local origem = self.Entity.GetCFrame() * CFrame.new(0, 0, -3)
    local hitbox, carrier = HitboxSpawner.Spawn(self.Entity, origem, {
        CFrame.new(-2, 0, 0), CFrame.new(0, 0, 0), CFrame.new(2, 0, 0),   -- 3 pontos lado a lado
    })
    hitbox:SetCastData({ CastType = "Spherecast", Radius = 1.5 })
    hitbox:OnUpdate(Behaviors.LinearMove(carrier, origem.LookVector, 50, 1))
    hitbox:OnHit(function(result)
        local e = DataManager.GetEntityFromInstance(result.Instance)
        if e and StateTable.CanAffect(self, e) then self:Damage(e, 15) end
    end)
    hitbox:OnStopped(function() HitboxSpawner.Cleanup(hitbox, carrier) end)
    hitbox:HitStart(1)
end,
`,
    desc: `O código acima monta à mão uma onda de três pontos que avança 50 studs/s por 1 segundo. O Spawn só cria o carrier e o hitbox; quem chama escolhe a forma (<code>SetCastData</code>), o movimento (<code>OnUpdate</code>), o que fazer no acerto e liga com <code>HitStart</code>. Guarde os dois retornos: o carrier precisa ser destruído junto (o <code>Cleanup</code> no <code>OnStopped</code>). Para formas comuns, use os ${L("api.HitboxPresets", "Presets")}.`,
  });

  X("api.HitboxSpawner.SetCarrierCFrame", {
    code: `
-- um orbe que gira em volta de quem casta
local t = 0
hitbox:OnUpdate(function(dt)
    t += dt
    local centro = self.Entity.GetCFrame()
    HitboxSpawner.SetCarrierCFrame(carrier, centro * CFrame.Angles(0, t * 4, 0) * CFrame.new(0, 0, -6))
end)
`,
    desc: `O código acima move o carrier em órbita a cada frame. Mova o carrier sempre por esta função, dentro do <code>OnUpdate</code>: ela ignora um carrier já destruído e é o único ponto que escreve a posição dele.`,
  });

  X("api.HitboxSpawner.Cleanup", {
    code: `
hitbox:OnStopped(function()
    HitboxSpawner.Cleanup(hitbox, carrier)
end)
`,
    desc: `O código acima destrói o hitbox e o carrier quando o hitbox para (pela duração ou por <code>HitStop</code>). O hitbox sozinho não destrói o carrier: sem isto, a peça invisível fica no workspace para sempre. Os Presets já fazem isso.`,
  });

  X("api.HitboxSpawner.BuildDefaultFilter", {
    code: `
-- excluir quem casta e o próprio escudo dele
local params = HitboxSpawner.BuildDefaultFilter(self.Entity, { workspace.Escudos[self.Entity.ID] })
local hitbox, carrier = HitboxSpawner.Spawn(self.Entity, origem, nil, params)
`,
    desc: `O código acima monta o filtro de raycast padrão (exclui o corpo de quem casta) com uma peça extra excluída, e o passa ao Spawn.`,
  });

  X("api.HitboxBehaviors.LinearMove", {
    code: `
-- desacelera: a velocidade é uma função do tempo
hitbox:OnUpdate(Behaviors.LinearMove(carrier, direcao, function(t, dur) return 80 * (1 - t / dur) end, 1.2))
`,
    desc: `O código acima move o projétil em linha reta, começando a 80 studs/s e parando no fim de 1,2 s. Direção e velocidade aceitam valor fixo ou função <code>(elapsed, duration)</code>, como nas Forces. O behavior não desliga o hitbox: a duração real é a do <code>HitStart</code>.`,
  });

  X("api.HitboxBehaviors.Homing", {
    code: `
local alvo = DataManager.Get(ctx.input.Target)
hitbox:OnUpdate(Behaviors.Homing(carrier, function() return alvo and alvo.GetRoot() end, 60, math.rad(180)))
`,
    desc: `O código acima faz o projétil perseguir o root do alvo a 60 studs/s, girando no máximo 180° por segundo (sem o 4º argumento, a curva é perfeita). Se o alvo sumir, o projétil segue na última direção.`,
  });

  X("api.HitboxBehaviors.ExpandUniform", {
    code: `
hitbox:SetCastData({ CastType = "Spherecast", Radius = 1 })
hitbox:OnUpdate(Behaviors.ExpandUniform(hitbox, 20, 15))   -- +20 de raio por s, até 15
`,
    desc: `O código acima faz uma esfera crescer de 1 a 15 de raio (uma explosão que se expande). Serve para Spherecast; o raio para de crescer no máximo.`,
  });

  X("api.HitboxBehaviors.ExpandDirectional", {
    code: `
hitbox:SetCastData({ CastType = "Blockcast", Size = Vector3.new(0.5, 2, 1) })
hitbox:OnUpdate(Behaviors.ExpandDirectional(hitbox, "Z", 40, 20))   -- estica para a frente até 20
`,
    desc: `O código acima estica uma caixa num eixo local (um raio laser que se alonga). Serve para Blockcast; o eixo é <code>"X"</code>, <code>"Y"</code> ou <code>"Z"</code>.`,
  });

  X("api.HitboxPresets.HomingBolt", {
    code: `
onStart = function(self, ctx)
    local alvo = ctx.input.Target and DataManager.Get(ctx.input.Target)
    if not alvo then return self:Fizzle() end
    local acertados = {}
    local hitbox = Presets.HomingBolt(self.Entity, self.Entity.GetCFrame(),
        function() return alvo.GetRoot() end, 70, 2, 3)
    hitbox:OnHit(function(result)
        local e = DataManager.GetEntityFromInstance(result.Instance)
        if e and not acertados[e] and StateTable.CanAffect(self, e) then
            acertados[e] = true
            self:Damage(e, 20)
            hitbox:HitStop()   -- some no primeiro acerto
        end
    end)
end,
`,
    desc: `O código acima dispara um projétil teleguiado (velocidade 70, raio 2, vida de 3 s) no alvo que o player clicou. O preset já se limpa quando para. O <code>acertados</code> evita contar o mesmo corpo duas vezes (várias peças dele podem ser tocadas no mesmo frame).`,
  });

  X("api.HitboxPresets.ExpandingRing", {
    code: `
onStart = function(self)
    local atingidos = {}
    local anel = Presets.ExpandingRing(self.Entity, self.Entity.GetCFrame(), 12, 2, 30, 2, 0.6)
    for _, ponto in anel do
        ponto.hitbox:OnHit(function(result)
            local e = DataManager.GetEntityFromInstance(result.Instance)
            if e and not atingidos[e] and StateTable.CanAffect(self, e) then
                atingidos[e] = true
                self:Damage(e, 25)
            end
        end)
    end
end,
`,
    desc: `O código acima é uma onda de choque: 12 esferas saem do centro a 30 studs/s por 0,6 s. Cada ponto é um hitbox separado, então o <code>OnHit</code> é conectado em cada um, e a tabela <code>atingidos</code> é compartilhada para cada alvo levar dano uma vez só.`,
  });

  X("api.HitboxPresets.ExpandingCone", {
    code: `
local hitbox = Presets.ExpandingCone(self.Entity, self.Entity.GetCFrame() * CFrame.new(0, 0, -2), "X", 40, 10, 0.25)
hitbox:OnHit(function(result)
    local e = DataManager.GetEntityFromInstance(result.Instance)
    if e and StateTable.CanAffect(self, e) then self:Damage(e, 18) end
end)
`,
    desc: `O código acima é um corte horizontal: uma caixa fina à frente de quem casta se abre no eixo X até 10 de largura em 0,25 s.`,
  });

  // ================================================================ MinionFactory / ComboWindow
  X("api.MinionFactory.Spawn", [
    {
      t: "invocar",
      code: `
local MinionFactory = require(game.ServerStorage.Modules.MinionFactory)

onStart = function(self)
    local onde = self.Entity.GetCFrame() * CFrame.new(3, 0, 0)
    local lobo = MinionFactory.Spawn("Lobo", onde, self.Entity)
    if lobo and lobo:HasComponent(Component.Affiliation) then
        lobo.SetTeam(self.Entity.GetTeam())
    end
end,
`,
      desc: `O código acima invoca um lobo ao lado de quem casta, a partir do blueprint <code>Blueprints/Lobo</code>, e o põe no mesmo time. Com o 3º argumento, o lobo herda as reações do invocador marcadas com <code>Inherit</code> (o on-hit de um buff, por exemplo).`,
    },
    {
      t: "minion que herda o on-hit",
      code: `
-- no invocador: a reação marcada com Inherit passa para os minions
self.Entity:Listen({
    Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.onHit,
    Inherit = { Generations = 1 },
    Action = function(ctx) ctx.damage += 3 end,
})
MinionFactory.Spawn("Lobo", onde, self.Entity)   -- o lobo bate +3 também
`,
      desc: `O código acima dá +3 de dano aos golpes do invocador e, pela herança, aos do lobo. Com <code>Generations = 1</code>, a reação passa para os filhos diretos, mas um minion invocado pelo lobo não a recebe.`,
    },
  ]);

  X("api.MinionFactory.Register", {
    code: `
MinionFactory.Register("Totem", {
    Components = { "Character", "Health", "Status" },
    Configs = { Health = { MaxHP = 60 } },
    Model = game.ServerStorage.Assets.Totem,
})
local totem = MinionFactory.Spawn("Totem", cframe)
`,
    desc: `O código acima registra um blueprint em código, sem criar módulo na pasta Blueprints. Um blueprint dá a lista de componentes, os configs e o Model (clonado e posicionado) ou uma função <code>BuildModel(cframe)</code> que monta o corpo.`,
  });

  X("api.ComboWindow.Mark", {
    code: `
local ComboWindow = require(game.ServerStorage.DataBase.SkillDatabase.BaseSkills).ComboWindow

-- skill A: o lançamento abre uma janela de 1,2 s
onHit = function(self, hit)
    self:Damage(hit.target, 10, { Hit = hit })
    ComboWindow.Mark(self.Entity, "Lancamento", 1.2, { alvo = hit.target }, self.Runner)
end,
`,
    desc: `O código acima marca que um lançamento acabou de acontecer, guardando o alvo. A janela é um status interno na entidade e dura 1,2 s; marcar de novo renova. A entidade precisa do componente Status.`,
  });

  X("api.ComboWindow.Consume", {
    code: `
-- skill B: se a janela está aberta, vira o finalizador aéreo
onStart = function(self)
    local combo = ComboWindow.Consume(self.Entity, "Lancamento")
    if combo and combo.alvo and combo.alvo.Active then
        self:Damage(combo.alvo, 40)
    end
end,
`,
    desc: `O código acima lê e fecha a janela: a skill B não precisa conhecer a skill A, só o nome do marcador. O retorno é o payload (uma tabela vazia se a janela foi aberta sem payload) ou <code>nil</code> se a janela estava fechada.`,
  });

  X("api.ComboWindow.Peek", {
    code: `
if ComboWindow.Peek(self.Entity, "Lancamento") then
    self.Entity.PlayFromLib("M1", "Aereo")
end
`,
    desc: `O código acima confere se a janela está aberta sem fechá-la (para escolher uma animação, por exemplo). Para usar o combo, chame <code>Consume</code>.`,
  });

  // ================================================================ Input
  X("api.Intents.NewEvent", {
    code: `
local Intents = require(game.ReplicatedStorage.Input.Intents)

local toque = Intents.NewEvent(Intents.Id.Primary, Intents.Kind.Activate, Intents.Gesture.Press)
local mira = Intents.NewEvent(Intents.Id.Ability2, Intents.Kind.Activate, Intents.Gesture.Press, nil,
    { Target = alvo.ID, Point = alvo.GetPosition() })
SkillHandler.HandleIntent(npc.ID, mira)
`,
    desc: `O código acima cria dois eventos de input: um toque simples e um com alvo e ponto. O evento é congelado (imutável). É o único construtor de InputEvent: NPC, script e o próprio servidor criam eventos por aqui. O payload deve vir já validado (de código do servidor, ou passado por <code>SanitizePayload</code>).`,
  });

  X("api.Intents.IsButton", {
    code: `
RemoteBotao.OnServerEvent:Connect(function(player, intent)
    if not Intents.IsButton(intent) then return end
    -- intent é uma das conhecidas: Primary, Dash, Ability1...
end)
`,
    desc: `O código acima valida uma intent que chegou da rede. Aceita qualquer valor e só devolve <code>true</code> para os IDs de <code>Intents.Id</code>.`,
  });

  X("api.Intents.SanitizePayload", {
    code: `
RemoteMira.OnServerEvent:Connect(function(player, bruto)
    local payload = Intents.SanitizePayload(bruto)
    if not payload or not payload.Point then return end
    -- payload.Point é um Vector3 finito dentro do mundo; o alcance é com você
end)
`,
    desc: `O código acima limpa um payload de alvo/ponto vindo de um cliente: só passa <code>Target</code> string de 1 a 64 caracteres e <code>Point</code> Vector3 finito com coordenadas até 1e6; o resto vira <code>nil</code>. Se o alvo existe e está ao alcance, a skill confere.`,
  });

  X("api.GestureResolver.new", {
    code: `
local GestureResolver = require(game.ReplicatedStorage.Input.GestureResolver)

local resolver = GestureResolver.new(Intents.Id.Ability1, function(evento)
    print(evento.Kind, evento.Gesture, evento.HeldTime)
end)
`,
    desc: `O código acima cria um reconhecedor de gestos para uma intent. Ele não conhece Roblox, player nem skill: recebe Press/Release com horário e devolve eventos no <code>sink</code>. O InputValidator mantém um por intent de cada player.`,
  });

  X("api.GestureResolver.Normalize", {
    code: `
local cfg = GestureResolver.Normalize({ Hold = true, Tap = true })
print(cfg.hold, cfg.tap)   -- 0.3  true   (true = Intents.Defaults.HoldTime)
print(GestureResolver.Normalize(nil))   -- nil: Press cru
`,
    desc: `O código acima converte o <code>data.input</code> de uma skill na configuração interna do resolver. <code>true</code> vira o tempo padrão de <code>Intents.Defaults</code>; sem declaração, o resultado é <code>nil</code> e o botão ativa no instante do Press.`,
  });

  X("api.GestureResolver.Press", {
    code: `
local cfg = GestureResolver.Normalize({ Hold = 0.4 })
resolver:Press(os.clock(), cfg)
task.wait(0.5)
resolver:Release(os.clock())
-- sink: Activate Hold (em 0,4 s) ... Release (HeldTime 0.5)
`,
    desc: `O código acima simula segurar o botão por 0,5 s numa skill de Hold de 0,4 s: o resolver emite Activate(Hold) ao passar de 0,4 s e o Release ao soltar. A configuração é passada no Press porque é a da skill no slot naquele momento.`,
  });

  X("api.GestureResolver.Release", {
    code: `
-- toque curto numa skill com Hold e Tap: vira Tap no Release
local cfg = GestureResolver.Normalize({ Hold = 0.4, Tap = true })
resolver:Press(os.clock(), cfg)
resolver:Release(os.clock() + 0.1, { Point = Vector3.new(10, 0, 5) })
-- sink: Activate Tap (HeldTime 0.1, Point = 10, 0, 5)
`,
    desc: `O código acima solta antes do tempo de Hold: o resolver emite Activate(Tap) no Release, sem Release depois (o Tap ativa já com o botão solto). O payload do Release substitui o do Press nos eventos que ele gera.`,
  });

  X("api.GestureResolver.Cancel", {
    code: `
-- o player morreu segurando o botão
resolver:Cancel(os.clock())          -- emite o Release pendente
-- a entidade já foi destruída: não emita nada
resolver:Cancel(os.clock(), true)
`,
    desc: `O código acima encerra o ciclo de um botão no meio (morte, respawn, troca de corpo). Sem <code>silent</code>, se algo foi ativado com o botão apertado, o Release é emitido, para a skill de Hold não ficar carregando para sempre; com <code>silent</code>, nada sai.`,
  });

  X("api.InputService.SetPayloadProvider", [
    {
      t: "alvo e ponto do mouse",
      code: `
-- LocalScript
local InputService = require(game.Players.LocalPlayer.PlayerScripts.InputService)
local mouse = game.Players.LocalPlayer:GetMouse()

InputService.SetPayloadProvider(function(intent)
    local model = mouse.Target and mouse.Target:FindFirstAncestorOfClass("Model")
    return { Target = model and model:GetAttribute("EntityID"), Point = mouse.Hit.Position }
end)
`,
      desc: `O código acima faz todo envio de input levar a entidade sob o mouse e o ponto do mundo onde o mouse aponta. No servidor, a skill lê <code>ctx.input.Target</code> e <code>ctx.input.Point</code>.`,
    },
    {
      t: "só para uma intent",
      code: `
InputService.SetPayloadProvider(function(intent)
    if intent ~= Intents.Id.Ability2 then return nil end   -- só a habilidade de mira
    return { Point = mouse.Hit.Position }
end)
`,
      desc: `O código acima manda o ponto só com a Ability2; as outras intents vão sem payload. Para desligar o provider, passe <code>nil</code>.`,
    },
  ]);

  X("api.InputService.Press", {
    code: `
-- um botão de tela feito à mão (sem a tag InputButton)
local botao = script.Parent.BotaoUlt
botao.MouseButton1Down:Connect(function() InputService.Press(Intents.Id.Ultimate, botao) end)
botao.MouseButton1Up:Connect(function() InputService.Release(Intents.Id.Ultimate, botao) end)
`,
    desc: `O código acima liga um botão de tela à Ultimate. A <code>source</code> (aqui, o próprio botão) identifica quem apertou: a intent só é solta quando todas as fontes que a apertaram soltarem (teclado e botão juntos não geram dois casts). Um GuiButton com a tag <code>InputButton</code> e o atributo <code>Intent</code> faz isso sem código.`,
  });

  X("api.InputService.Release", {
    code: `
botao.MouseButton1Up:Connect(function()
    InputService.Release(Intents.Id.Ultimate, botao, { Point = mouse.Hit.Position })
end)
`,
    desc: `O código acima solta a intent com um ponto próprio do momento de soltar (útil para "segure, mire e solte"). Release de uma fonte que não apertou é ignorado.`,
  });

  X("api.InputService.ReleaseAll", {
    code: `
game:GetService("UserInputService").WindowFocusReleased:Connect(function()
    InputService.ReleaseAll()
end)
`,
    desc: `O código acima solta todas as intents quando a janela do jogo perde o foco (alt-tab), para nenhuma skill de Hold ficar "presa" segurando.`,
  });

  X("api.InputService.Rebind", {
    code: `
-- tela de remap: o player escolheu Q e o botão Y do controle para a Ultimate
InputService.Rebind(Intents.Id.Ultimate, { Enum.KeyCode.Q, Enum.KeyCode.ButtonY })
`,
    desc: `O código acima troca as teclas da Ultimate em runtime. A lista substitui a anterior inteira e pode misturar KeyCode e UserInputType (mouse). Aqui <code>Enum</code> é o do Roblox.`,
  });

  X("api.InputService.Init", {
    code: `
-- InputController.client (já existe no projeto)
local InputService = require(script.Parent.InputService)
InputService.Init()
`,
    desc: `O código acima liga o serviço de input do cliente (bindings, botões de tela, envio ao servidor). O <code>InputController.client</code> do projeto já faz isso; não chame de novo.`,
  });

  // ================================================================ Física e rede
  X("api.NetworkView.Lag", {
    code: `
local NetworkView = require(game.ServerScriptService.Modules.Physics.NetworkView)
print(string.format("%.2f s de atraso", NetworkView.Lag(player)))   -- 0.42 s de atraso
`,
    desc: `O código acima mostra com quanto atraso o servidor vê o corpo do player: <code>Client_View_Lag</code> mais uma parte do ping (<code>Client_View_Ping_Factor</code>), dos Settings de física.`,
  });

  X("api.NetworkView.PredictedShift", {
    code: `
-- o raio cai onde o player está agora, não onde o servidor o viu
local shift = NetworkView.PredictedShift(alvo.GetRoot())
local ponto = alvo.GetPosition() + (shift or Vector3.zero)
VFXManager.PlayNear(ponto, 200, "Raio", { Position = ponto })
for _, part in workspace:GetPartBoundsInRadius(ponto, 5) do
    local e = DataManager.GetEntityFromInstance(part)
    if e == alvo then alvo.TakeDamage(30) break end
end
`,
    desc: `O código acima corrige a posição de um alvo player pelo atraso de rede (velocidade vista × atraso do dono) antes de decidir se o raio o acertou; sem a correção, um player correndo seria atingido onde estava 0,4 s atrás. Num corpo do servidor (NPC) não há atraso e o retorno é <code>nil</code>, daí o <code>or Vector3.zero</code>. As zonas já usam esta correção sozinhas.`,
  });

  X("api.CollisionGroups.Assign", {
    code: `
local CollisionGroups = require(game.ServerScriptService.Modules.Physics.CollisionGroups)

local restaura = CollisionGroups.Assign(alvo.Instance, CollisionGroups.Grabbed)
-- ... o alvo está agarrado e não colide com outros agarrados nem com quem agarrou
restaura()
`,
    desc: `O código acima põe todas as peças do alvo no grupo de "agarrado" e depois devolve cada peça ao grupo que tinha. Agarrados continuam colidindo com o mundo. Model <code>nil</code> devolve uma função que não faz nada.`,
  });

  X("api.GlobalAntiCheat.GetEntityID", {
    code: `
local AntiCheat = require(game.ServerScriptService.Modules.GlobalAntiCheat)
local id = AntiCheat.GetEntityID(player)
print(id)   -- Player_123456, Entity_987654 (possuindo) ou nil (Lock)
`,
    desc: `O código acima diz para qual entidade o input do player está indo agora: o corpo dele, um corpo possuído ou ninguém (input cortado por Lock). É a pergunta que todo handler de input faz antes de agir.`,
  });

  X("api.GlobalAntiCheat.GetControlledEntityId", {
    code: `
local dirigida = AntiCheat.GetControlledEntityId(player)
local e = dirigida and DataManager.Get(dirigida)
if e then mostrarHUD(player, e) end
`,
    desc: `O código acima mostra a HUD da entidade que o player dirige, mesmo durante um Lock (uma cutscene não troca o corpo que ele controla, só corta o input).`,
  });

  X("api.GlobalAntiCheat.GetNativeEntityId", {
    code: `
local nativo = AntiCheat.GetNativeEntityId(player)
if AntiCheat.GetControlledEntityId(player) ~= nativo then
    print(player.Name, "está fora do próprio corpo")
end
`,
    desc: `O código acima detecta se o player está possuindo outro corpo, comparando a entidade dirigida com o corpo nativo dele.`,
  });

  X("api.GlobalAntiCheat.GetMovementCorrections", {
    code: `
game.Players.PlayerRemoving:Connect(function(player)
    local n = AntiCheat.GetMovementCorrections(player)
    if n > 20 then warn(player.Name, "teve", n, "correções de movimento") end
end)
`,
    desc: `O código acima registra players com muitas correções de movimento (velocidade ou teleporte recusados) desde o último spawn. Algumas correções são normais com ping alto; muitas indicam exploit ou um ajuste de Settings.`,
  });

  X("api.GlobalAntiCheat.LockPlayerInput", {
    code: `
AntiCheat.LockPlayerInput(player)
tocarCutscene(player)
AntiCheat.UnlockPlayerInput(player)
`,
    desc: `O código acima corta todo o input do player na raiz durante uma cutscene, sem precisar do componente Control. Devolve <code>false</code> se o player não está registrado ou já estava travado. Com Control, prefira <code>entity.Lock()</code>.`,
  });

  X("api.GlobalAntiCheat.UnlockPlayerInput", {
    code: `
if AntiCheat.UnlockPlayerInput(player) then
    print("input devolvido para", AntiCheat.GetEntityID(player))
end
`,
    desc: `O código acima devolve o input ao player, para a entidade que ele dirigia antes do Lock (ou a que uma possessão durante o Lock deixou). Devolve <code>false</code> se não havia Lock.`,
  });

  X("api.GlobalAntiCheat.SetControlledEntity", {
    code: `
-- o que o Control faz ao possuir: o input do player vai para o golem
AntiCheat.SetControlledEntity(player, golem.ID, true)   -- true = o WASD nativo é suspenso
`,
    desc: `O código acima redireciona o input do player para outra entidade. O jogo deve usar ${L("api.Control.Possess", "Possess")}, que também cuida da pilha, da IA, da rede e da HUD; esta função é a peça de baixo.`,
  });

  // ================================================================ Cliente e utilitários
  X("api.VFX.PlayAll", {
    code: `
local VFXManager = require(game.ServerScriptService.Modules.VFX.VFXManager)
VFXManager.PlayAll("Tremor", { Intensidade = 0.8, Duracao = 1.5 })
`,
    desc: `O código acima pede a todos os clientes o efeito <code>Tremor</code>. O servidor só manda o nome e os dados; quem constrói é a função <code>Registry.Tremor</code> no <code>VFXRegistry</code> do cliente.`,
  });

  X("api.VFX.PlayNear", {
    code: `
onHit = function(self, hit)
    self:Damage(hit.target, 10, { Hit = hit })
    VFXManager.PlayNear(hit.position, 200, "Impacto", { Position = hit.position, Normal = hit.normal })
end,
`,
    desc: `O código acima toca o efeito de impacto só para os players a até 200 studs do acerto, poupando rede de quem está longe.`,
  });

  X("api.SoundManager.PlayOneShot3D", {
    code: `
local SoundManager = require(game.ServerScriptService.Modules.Audio.SoundManager)
SoundManager.PlayOneShot3D(hit.position, "rbxassetid://1234567", { Volume = 0.8, Pitch = 1.1 })
`,
    desc: `O código acima toca um som de impacto no ponto do acerto. O som é criado numa âncora invisível destruída ao fim (ou depois de <code>MaxLifetime</code>, 10 s por padrão).`,
  });

  X("api.SoundManager.PlayAttached", {
    code: `
-- motor do voo: o mesmo Sound é reaproveitado a cada voo pela key
local som = SoundManager.PlayAttached(self.Entity.GetRoot(), "rbxassetid://7654321",
    { Looped = true, Volume = 0.5 }, "SomDoVoo")
self:Own(function() som:Stop() end)
`,
    desc: `O código acima toca um som em loop preso ao root enquanto a skill durar. Com <code>key</code>, um Sound de mesmo nome já existente na instância é reaproveitado em vez de criar outro.`,
  });

  X("api.CameraOverride.Enable", {
    code: `
-- LocalScript
local CameraOverride = require(game.Players.LocalPlayer.PlayerScripts.CameraOverride)
CameraOverride.Enable()
`,
    desc: `O código acima liga a câmera de ombro com lock suave. O ajuste fino (offset do ombro, distância, cone do lock) fica na tabela <code>Config</code> no topo do módulo.`,
  });

  X("api.CameraOverride.Disable", {
    code: `
-- abriu o inventário: câmera padrão do Roblox
CameraOverride.Disable()
`,
    desc: `O código acima desliga a câmera de ombro e devolve a câmera padrão.`,
  });

  X("api.CameraOverride.Toggle", {
    code: `
local UIS = game:GetService("UserInputService")
UIS.InputBegan:Connect(function(input, gp)
    if not gp and input.KeyCode == Enum.KeyCode.V then CameraOverride.Toggle() end
end)
`,
    desc: `O código acima alterna a câmera numa tecla própria (a tecla C já faz isso por padrão).`,
  });

  X("api.CameraOverride.IsActive", {
    code: `
if CameraOverride.IsActive() then
    mira.Visible = true
end
`,
    desc: `O código acima mostra a mira na tela só com a câmera de ombro ligada.`,
  });

  X("api.CameraOverride.GetCurrentTarget", {
    code: `
game:GetService("RunService").RenderStepped:Connect(function()
    local alvo = CameraOverride.GetCurrentTarget()
    marcador.Adornee = alvo and alvo:FindFirstChild("HumanoidRootPart")
    marcador.Enabled = alvo ~= nil
end)
`,
    desc: `O código acima põe um marcador (um BillboardGui) no Model travado pelo lock da câmera. Sem lock, devolve <code>nil</code>.`,
  });

  X("api.Logger.Channel", {
    code: `
local Log = require(game.ReplicatedStorage.Logger).Channel("Loja")

Log.Debug("abrindo loja para", player.Name)
Log.Info("compra:", item, preco)
Log.Warn("item sem preço:", item)
Log.WarnOnce("SemEstoque:" .. item, "estoque zerado:", item)   -- 1ª vez em Warn, depois só em Debug
`,
    desc: `O código acima cria o canal <code>Loja</code> e escreve nos níveis. O que aparece no Output depende do nível global e do nível do canal no <code>LogConfig</code>: com <code>Level = "Info"</code>, o Debug some. <code>WarnOnce</code> evita inundar o Output com o mesmo aviso.`,
  });

  X("api.Logger.SetLevel", {
    code: `
local Logger = require(game.ReplicatedStorage.Logger)
Logger.SetLevel("Debug", "SkillHandler")   -- só este canal fica falante
Logger.SetLevel("Warn")                    -- o resto, só avisos e erros
`,
    desc: `O código acima muda os níveis em runtime (pela barra de comandos do Studio, durante um teste): um canal em Debug para investigar um problema, e o resto quieto.`,
  });

  X("api.AnimationLib.ForSkill", {
    code: `
local lib = require(game.ServerStorage.Modules.Animation.AnimationLib)

-- a Ultimate da Schema roubada pelo personagem "Ashley"
local vista = lib.ForSkill("Schema", "Ashley")
print(vista.M1.M1Start)   -- o conjunto M1 da Schema (o kit dono da skill)
`,
    desc: `O código acima monta a vista de animações que uma skill da Schema enxerga em <code>self.charLib</code> quando quem casta é outro personagem: os conjuntos vêm do kit dono da skill e, só na falta, do kit de quem casta. A vista é só leitura e fica em cache por par de kits; o SkillRunner já a monta sozinho.`,
  });

  X("api.Utils.rotateTowards", {
    code: `
local Utils = require(game.ReplicatedStorage.Utils)

-- torreta que gira no máximo 90° por segundo em direção ao alvo
local direcao = Vector3.new(0, 0, -1)
game:GetService("RunService").Heartbeat:Connect(function(dt)
    local desejada = alvo.GetPosition() - torre.Position
    direcao = Utils.rotateTowards(direcao, desejada, math.rad(90) * dt)
    torre.CFrame = CFrame.lookAt(torre.Position, torre.Position + direcao)
end)
`,
    desc: `O código acima gira a torreta aos poucos em direção ao alvo. O ângulo máximo é por chamada, então multiplique pela variação de tempo. O retorno é unitário. É a mesma conta do <code>TurnRate</code> das Forces e do homing dos projéteis.`,
  });

  X("api.Utils.classifyDirection", {
    code: `
onStart = function(self, ctx)
    local id = ctx.direction and ctx.direction.Id or Utils.classifyDirection(
        self.Entity.GetDirection(), self.Entity.GetLookDirection())
    if id == "Back" then
        -- golpe de recuo
    end
end,
`,
    desc: `O código acima classifica o input de movimento em relação a quem olha: <code>Forward</code>, <code>ForwardRight</code>, <code>Right</code>, <code>BackRight</code>, <code>Back</code>, <code>BackLeft</code>, <code>Left</code>, <code>ForwardLeft</code> ou <code>None</code>. No contexto de dano, o mesmo valor já vem em <code>ctx.direction.Id</code>.`,
  });

  X("api.Utils.worldToLocalPlanar", {
    code: `
local localDir = Utils.worldToLocalPlanar(entity.GetDirection(), entity.GetLookDirection())
print(localDir.X, localDir.Z)   -- 1 0: andando para a direita; 0 -1: para trás
`,
    desc: `O código acima passa a direção de movimento para o espaço da câmera, no plano: X é o lado (direita positiva) e Z é a frente (frente positiva). Útil para misturar animações de andar de lado.`,
  });

  X("api.Utils.getRoot", {
    code: `
local root = Utils.getRoot(player.Character)
if root then print(root.Position) end
`,
    desc: `O código acima acha a HumanoidRootPart de um personagem. Em entidades, prefira <code>entity.GetRoot()</code>, que também cobre rigs sem HumanoidRootPart (PrimaryPart).`,
  });

  X("api.Utils.clamp", {
    code: `
local carga = Utils.clamp(ctx.input.HeldTime / 2, 0.2, 1)
`,
    desc: `O código acima limita a carga de uma skill de Hold entre 20% e 100%. Igual a <code>math.clamp</code>, e funciona no cliente e no servidor.`,
  });

  X("api.Utils.lerp", {
    code: `
local dano = Utils.lerp(10, 50, carga)   -- 10 sem carga, 50 com carga cheia
`,
    desc: `O código acima interpola o dano entre o mínimo e o máximo conforme a carga (de 0 a 1).`,
  });

  X("api.Utils.round", {
    code: `
textoDano.Text = tostring(Utils.round(dano))   -- 12.6 -> 13
`,
    desc: `O código acima arredonda o dano para o inteiro mais próximo na hora de mostrar.`,
  });

  X("api.Utils.sign", {
    code: `
local lado = Utils.sign(localDir.X)   -- -1 esquerda, 0 nenhum, 1 direita
`,
    desc: `O código acima reduz a componente lateral do movimento a -1, 0 ou 1, para escolher a animação de esquiva do lado certo.`,
  });

  X("api.Utils.percent", {
    code: `
barra.Text = math.floor(Utils.percent(entity.GetHP(), entity.GetMaxHP())) .. "%"
`,
    desc: `O código acima mostra a vida em porcentagem. Com o total zero, devolve 0 em vez de dividir por zero.`,
  });
})();

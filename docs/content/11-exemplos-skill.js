/*
  Exemplos de uso: skills (self dentro da skill, SkillHandler, SkillRunner, CooldownPolicy).
  Estilo e requires: ver o topo de 09-exemplos-nucleo.js. Os trechos com callbacks são pedaços do
  { data, callbacks } de um módulo de skill.
*/
(function () {
  var X = DOCS.example;

  // ================================================================ self
  X("api.skill.Damage", [
    {
      t: "golpe com Stun",
      code: `
onHit = function(self, hit)
    local ok, dano = self:Damage(hit.target, 12, { Hit = hit })
    if ok and dano > 0 then
        self:ApplyStatus(self.statusTable.States.Stun, { Target = hit.target, Duration = 0.4 })
    end
end,
`,
      desc: `O código acima causa 12 de dano em cada alvo que a hitbox da arma tocar e, se o dano entrou de fato, atordoa o alvo por 0,4 s. O retorno <code>ok, dano</code> distingue um golpe absorvido (iFrame, bloqueio total, cancelado no <code>PreDamage</code>) de um que tirou vida. <code>Hit = hit</code> leva o ponto do impacto para o contexto (efeitos e listeners leem em <code>ctx.hit</code>).`,
    },
    {
      t: "opções só deste golpe",
      code: `
onHit = function(self, hit)
    self:Damage(hit.target, 30, {
        Hit = hit,
        Traits = { Enum.Traits.TrueHit },          -- fura iFrame e bloqueio comum
        Effects = { StateTable.Status.Bleed },     -- sangra só neste golpe
        Inherited = { origem = "Finalizador" },    -- payload para o status on-hit
    })
end,
`,
      desc: `O código acima é um finalizador que fura a invulnerabilidade, aplica sangramento e marca a origem no payload. <code>Traits</code> e <code>Effects</code> somam às do <code>data</code> da skill só neste golpe; <code>Inherited</code> chega no <code>ctx.inherited</code> do status aplicado pelo golpe. Com <code>Prescaled = true</code>, o <code>DamageMult</code> de quem bate não é aplicado (use quando o valor já veio escalado).`,
    },
  ]);

  X("api.skill.ApplyStatus", [
    {
      t: "no alvo",
      code: `
onHit = function(self, hit)
    self:ApplyStatus(self.statusTable.Status.Bleed, { Target = hit.target })
end,
`,
      desc: `O código acima aplica sangramento em quem a skill acertar. O runner da skill vira o <code>Source</code> do status: as mortes pelo sangramento creditam quem casta e o <span class="badge out">OUT</span> <code>PreApplyStatus</code> chega nele antes do status entrar.`,
    },
    {
      t: "em si mesmo",
      code: `
onStart = function(self)
    -- invulnerável durante a esquiva
    self.iframeID = self:ApplyStatus(self.statusTable.Status.iFrame, { Duration = 0.3 })
end,
`,
      desc: `O código acima aplica iFrame na própria entidade por 0,3 s. Sem <code>Target</code>, o alvo é quem casta. O retorno é o ID da aplicação, para remover antes do fim se precisar; <code>nil</code> se o status não entrou.`,
    },
  ]);

  X("api.skill.StartHitbox", {
    code: `
data = { cooldown = 1, duration = 0.5, requires = { Component.Weapon } },
callbacks = {
    onStart = function(self)
        self:StartHitbox(self.data.duration)
    end,
    onHit = function(self, hit)
        -- hit = { target, position, normal, distance, instance, hitboxName, flags, segment }
        self:Damage(hit.target, 10, { Hit = hit })
    end,
},
`,
    desc: `O código acima liga a hitbox da arma pela duração da skill; cada alvo tocado chega no <code>onHit</code> desta skill, uma vez por sessão. A sessão é só desta ativação: outra skill que use a mesma arma ao mesmo tempo tem a dela, e os acertos não se misturam. A hitbox sai sozinha no fim do runner. Sem Weapon, não liga nada; o <code>requires</code> faz o motor recusar o cast antes.`,
  });

  X("api.skill.StopHitbox", {
    code: `
-- giro de 3 acertos: a cada 0,2 s a hitbox reinicia e pode acertar os mesmos alvos
onStart = function(self)
    self.acertos, self.t = 1, 0
    self:StartHitbox(0.2)
end,
onStep = function(self, dt)
    self.t += dt
    if self.t >= 0.2 and self.acertos < 3 then
        self.t, self.acertos = 0, self.acertos + 1
        self:StopHitbox()
        self:StartHitbox(0.2)
    end
end,
`,
    desc: `O código acima faz um golpe que acerta o mesmo alvo três vezes. Uma sessão de hitbox acerta cada alvo uma vez só; <code>StopHitbox</code> desliga a sessão desta skill e zera a lista de já acertados, e o <code>StartHitbox</code> seguinte começa do zero. Para apagar a hitbox da arma inteira (não é o caso aqui), existe ${L("api.Weapon.DestroyHitbox")}.`,
  });

  X("api.skill.Listen", [
    {
      t: "redução de dano enquanto a skill durar",
      code: `
onStart = function(self)
    self:Listen({
        Role = Enum.Roles.IN, Breakpoint = Enum.Breakpoints.PreDamage,
        Action = function(ctx) ctx.damage *= 0.5 end,
    })
end,
`,
      desc: `O código acima corta pela metade o dano que quem casta recebe, enquanto a skill estiver ativa. Não há limpeza a escrever: o <code>Owner</code> é o runner, e a inscrição sai sozinha quando a skill termina, por qualquer motivo.`,
    },
    {
      t: "lifesteal durante a skill",
      code: `
onStart = function(self)
    self:Listen({
        Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.OnDamage,
        Query = { None = { Enum.Traits.DOT } },
        Action = function(ctx)
            self.Entity.Heal((ctx.actualDamage or 0) * 0.25, { Source = self.Runner })
        end,
    })
end,
`,
      desc: `O código acima cura quem casta em 25% de todo dano direto que ele causar durante a skill (não só o desta skill: <span class="badge out">OUT</span> <code>OnDamage</code> chega para todo dano do qual a entidade é dona).`,
    },
  ]);

  X("api.skill.Own", {
    code: `
onStart = function(self)
    local escudo = Instance.new("Part")
    escudo.Shape, escudo.Size = Enum.PartType.Ball, Vector3.one * 8
    escudo.Anchored, escudo.CanCollide, escudo.Transparency = true, false, 0.6
    escudo.CFrame = self.Entity.GetCFrame()
    escudo.Parent = workspace
    self:Own(function() escudo:Destroy() end)
end,
`,
    desc: `O código acima cria uma esfera visual e entrega a limpeza ao runner: ela é destruída no fim da skill, seja por duração, cancelamento, morte, interrupção ou erro, antes do <code>onEnd</code>. Se o <code>Own</code> for chamado depois que a skill já acabou (um acerto atrasado, por exemplo), a limpeza roda na hora em vez de vazar.`,
  });

  X("api.skill.Stop", {
    code: `
onRelease = function(self, ctx)
    local carga = math.clamp(ctx.input.HeldTime / 2, 0.2, 1)
    self:Damage(self.alvo, 50 * carga)
    self:Stop(false)        -- fim normal (motivo "stop")
end,
onStep = function(self, dt)
    if not self.alvo.IsAlive() then
        self:Stop(true)     -- cancelamento: roda o onCancel (motivo "cancel")
    end
end,
`,
    desc: `O código acima encerra a skill de dois jeitos: ao soltar o botão, fim normal; se o alvo morrer no meio, cancelamento. A diferença chega no <code>ctx.reason</code> do <code>onEnd</code> e na política de cooldown (o refund pode devolver o cooldown em cancelamento, se a skill declarar). Num cancelamento, o <code>onCancel</code> da skill pode recusar devolvendo <code>false</code>.`,
  });

  X("api.skill.Fizzle", {
    code: `
onStart = function(self, ctx)
    local alvo = ctx.input.Target and DataManager.Get(ctx.input.Target)
    if not alvo or (alvo.GetPosition() - self.Entity.GetPosition()).Magnitude > 40 then
        return self:Fizzle()
    end
    self.alvo = alvo
end,
`,
    desc: `O código acima desiste do cast quando não há alvo ou ele está longe demais. O motivo <code>fizzle</code> devolve o cooldown inteiro por padrão (<code>Enum.CooldownDefaults.refund</code>): para o player, é como se não tivesse apertado.`,
  });

  X("api.skill.CommitCooldown", {
    code: `
data = {
    cooldown = 6, duration = 0.5,
    cooldownPolicy = { start = Enum.CooldownStart.Manual },
},
callbacks = {
    onStart = function(self) self:StartHitbox(self.data.duration) end,
    onHit = function(self, hit)
        self:Damage(hit.target, 25, { Hit = hit })
        self:CommitCooldown()   -- só entra em cooldown se acertou
    end,
},
`,
    desc: `O código acima faz uma skill que só gasta o cooldown se acertar alguém: errou, pode usar de novo na hora. Com <code>start = Manual</code>, nada é cobrado no cast; o <code>CommitCooldown</code> cobra uma vez por ativação (as chamadas seguintes devolvem <code>false</code>). Sem a política Manual, a chamada avisa e não faz nada.`,
  });

  X("api.skill.GetRemainingTime", {
    code: `
onStep = function(self, dt)
    local resta = self:GetRemainingTime()
    if resta and resta < 1 and not self.avisou then
        self.avisou = true
        VFXManager.PlayNear(self.Entity.GetPosition(), 150, "EscudoPiscando", { Entity = self.Entity.ID })
    end
end,
`,
    desc: `O código acima toca um aviso quando falta menos de 1 segundo para a skill acabar. O tempo é contado pela duração (<code>self.runtimeDuration</code> ou <code>data.duration</code>) a partir do Running; durante o castTime, devolve a duração inteira. Skill sem duração devolve <code>nil</code>.`,
  });

  X("api.skill.endSkill", {
    code: `
onHit = function(self, hit)
    if hit.target.GetActiveTags()[Enum.Tags.block] then
        self:endSkill(true, "bloqueado")   -- motivo próprio do jogo
    end
end,
onEnd = function(self, ctx)
    if ctx.reason == "bloqueado" then
        self.Entity.ApplyStatus(self.statusTable.States.Stun, { Duration = 1 })
    end
end,
`,
    desc: `O código acima encerra a skill com um motivo próprio quando ela bate num alvo bloqueando, e pune quem casta no <code>onEnd</code>. O motivo chega em <code>ctx.reason</code> no <code>onCancel</code>, no <code>onEnd</code> e no <span class="badge out">OUT</span> <code>onEnd</code>. Um motivo que não está em <code>Enum.EndReasons</code> não tem refund de cooldown.`,
  });

  X("api.skill.Recast", {
    code: `
-- o que o SkillHandler faz quando o botão é apertado com a skill viva:
if runner:Recast(true) then          -- a skill tem onRecast?
    runner:Recast(nil, event)        -- roda o onRecast com o input novo
end

-- dentro da skill, o mesmo pode ser disparado por ela mesma:
onStep = function(self, dt)
    if self.rajadaPendente then self.rajadaPendente = false; self:Recast() end
end,
`,
    desc: `O código acima mostra os dois usos. O motor chama <code>Recast</code> no toque seguinte de uma skill com <code>onRecast</code> ainda viva (é assim que o M1 vira um combo de dois golpes); com <code>checkOnly = true</code>, só pergunta se existe <code>onRecast</code>. Chamado de dentro, dispara o próprio <code>onRecast</code> sem passar pelo cooldown de recast.`,
  });

  X("api.skill.TriggerAction", {
    code: `
-- o que o StatusComponent faz quando a entidade tem a tag block:
local novoDano = runnerDoBloqueio:TriggerAction(hitCtx)
if novoDano then hitCtx.damage = novoDano end

-- e o onTrigger do status de bloqueio decide:
onTrigger = function(self, hitCtx)
    if hitCtx.damage > 40 then return nil end   -- golpe pesado demais: não bloqueia
    return hitCtx.damage * 0.2                   -- bloqueia 80%
end,
`,
    desc: `O código acima mostra o caminho do bloqueio: o motor chama <code>TriggerAction</code> no runner do status que tem a tag <code>block</code>, e ele roda o <code>onTrigger</code> (ou, sem ele, o <code>data.block</code> declarado). O retorno é o dano novo, <code>true</code> (status barrado, num escudo de status) ou <code>nil</code> (não bloqueia). O jogo escreve o <code>onTrigger</code>; quem chama <code>TriggerAction</code> é o motor.`,
  });

  // ================================================================ SkillHandler
  X("api.SkillHandler.HandleIntent", [
    {
      t: "NPC aperta um botão",
      code: `
local SkillHandler = require(game.ServerScriptService.Modules.SkillHandler)
local Intents = require(game.ReplicatedStorage.Input.Intents)

local ok, skill, cooldown = SkillHandler.HandleIntent(npc.ID,
    Intents.NewEvent(Intents.Id.Primary, Intents.Kind.Activate, Intents.Gesture.Press))
if ok then print(skill, "castada; cooldown", cooldown) end
`,
      desc: `O código acima faz um NPC usar a skill do slot Primary, pelo mesmo caminho que o botão de um player usa: canCast, morte, maxInstances, recast, cooldown e ActionState são checados igual. O retorno diz se o cast aconteceu e, numa ativação, o nome da skill e o cooldown que ficou.`,
    },
    {
      t: "segurar e soltar",
      code: `
local id = Intents.Id.Ability1
SkillHandler.HandleIntent(npc.ID, Intents.NewEvent(id, Intents.Kind.Activate, Intents.Gesture.Hold))
task.wait(1.2)
SkillHandler.HandleIntent(npc.ID, Intents.NewEvent(id, Intents.Kind.Release, nil, 1.2))
`,
      desc: `O código acima faz a IA carregar uma skill de Hold por 1,2 s e soltar. O Release chega no <code>onRelease</code> da mesma ativação, com <code>ctx.input.HeldTime = 1.2</code>.`,
    },
  ]);

  X("api.SkillHandler.HandleMovementInput", {
    code: `
local function brain(entity, dt)
    local alvo = entity.alvoAtual
    if not alvo then
        SkillHandler.HandleMovementInput(entity.ID, Vector3.zero)   -- para
        return
    end
    SkillHandler.HandleMovementInput(entity.ID, alvo.GetPosition() - entity.GetPosition())
end
`,
    desc: `O código acima faz o NPC andar na direção do alvo, ou parar sem alvo. A direção é achatada no plano e normalizada (o tamanho do vetor não importa) e também vai para as entidades linkadas com <code>MirrorMovement</code>. Devolve <code>true</code> se a entidade ficou andando.`,
  });

  X("api.SkillHandler.HandleLookInput", {
    code: `
local function brain(entity, dt)
    local alvo = entity.alvoAtual
    if alvo then
        SkillHandler.HandleLookInput(entity.ID, alvo.GetPosition() - entity.GetPosition())
    end
end
`,
    desc: `O código acima faz o NPC olhar (mirar) para o alvo. Vira a mira 3D da entidade; a direção plana de combate é derivada dela. Vetor quase nulo é ignorado (devolve <code>false</code>).`,
  });

  X("api.SkillHandler.GetGestureSpec", {
    code: `
local spec = SkillHandler.GetGestureSpec(entity, Intents.Id.Ability1)
print(spec and spec.Hold, spec and spec.Tap)   -- 0.25  true
`,
    desc: `O código acima lê os gestos que a skill do slot Ability1 declarou em <code>data.input</code>. É o que o InputValidator usa para configurar o reconhecimento de gestos do botão; sem declaração, <code>nil</code> (Press cru).`,
  });

  // ================================================================ SkillRunner
  X("api.SkillRunner.new", {
    code: `
local SkillRunner = require(game.ServerScriptService.Modules.SkillRunner)
local SkillFactory = require(game.ServerScriptService.Modules.SkillFactory)

-- ao acabar, a skill deixa um "eco" que repete metade do golpe 1 s depois
onEnd = function(self, ctx)
    if ctx.reason ~= Enum.EndReasons.Duration then return end
    local eco = SkillRunner.new(SkillFactory.GetSkill(EcoModule), self.Entity, "Eco",
        Enum.Types.Skill, self.Runner.Lineage, nil, { forca = 0.5 })
    task.delay(1, function() eco:start() end)
end,
`,
    desc: `O código acima cria uma skill filha a partir de outra. Passar a <code>Lineage</code> do runner pai faz o eco entrar na mesma cadeia (crédito e limites); o último argumento vira o <code>ctx.inherited</code> do filho, só leitura. <code>SkillFactory.GetSkill</code> completa o módulo com os padrões (callbacks vazios, <code>maxInstances</code>). O runner só começa no <code>start()</code>.`,
  });

  X("api.SkillRunner.start", {
    code: `
local runner = SkillRunner.new(SkillFactory.GetSkill(modulo), entity, "Armadilha", Enum.Types.Skill)
if runner:start() == false then
    warn("a armadilha não começou (requires, cadeia larga demais ou erro no onStart)")
end
`,
    desc: `O código acima inicia um runner criado à mão e confere se ele começou. O start recusa sem os componentes de <code>data.requires</code> ou com a cadeia larga demais (<code>Enum.ChainLimits</code>), e um erro no <code>onStart</code> encerra o runner com o motivo <code>error</code>. Nos três casos devolve <code>false</code> e nada fica registrado.`,
  });

  X("api.SkillRunner.BuildContext", {
    code: `
local ctx = runner:BuildContext()
print(ctx.depth, table.concat(ctx.history, " > "))   -- 2   Schema_Dash > Bleed
print(ctx.sourceRunner and ctx.sourceRunner.skillName, ctx.inherited)
`,
    desc: `O código acima monta o mesmo contexto que os callbacks do runner recebem: profundidade na cadeia, histórico de nomes desde a raiz, o runner que o criou, o input e o <code>inherited</code>. Serve para ferramentas e depuração; dentro da skill, o contexto já chega como argumento.`,
  });

  X("api.SkillRunner.IsEnded", {
    code: `
-- uma torre guarda o runner do laser e só dispara outro quando o anterior acabou
if not torre.laser or torre.laser:IsEnded() then
    torre.laser = criarLaser(torre)
end
`,
    desc: `O código acima evita dois lasers ao mesmo tempo guardando o runner e perguntando se ele já terminou. Um runner encerrado nunca volta a rodar.`,
  });

  X("api.SkillRunner.Abort", {
    code: `
-- um sistema do jogo detecta estado inválido e derruba a skill
if not runner:IsEnded() and not runner.Entity.Active then
    runner:Abort()
end
`,
    desc: `O código acima encerra um runner com o motivo <code>error</code>, que o <code>onCancel</code> não pode recusar. É o que o motor faz quando um <code>onStart</code> ou <code>onStep</code> dá erro; o cooldown volta pelo refund padrão do motivo.`,
  });

  X("api.SkillRunner.Release", {
    code: `
-- entregar o "soltar botão" a um runner guardado, fora do SkillHandler
local evento = Intents.NewEvent(Intents.Id.Ability1, Intents.Kind.Release, nil, 0.8)
local rodou = runner:Release(evento)
print(rodou)   -- false se a skill não tem onRelease
`,
    desc: `O código acima entrega um Release diretamente a um runner. Roda o <code>onRelease</code> com o input novo (<code>ctx.input.HeldTime = 0.8</code>). Sem <code>onRelease</code>, não faz nada e a skill segue até a duração.`,
  });

  // ================================================================ CooldownPolicy
  X("api.CooldownPolicy.Transfer", {
    code: `
local CooldownPolicy = require(game.ServerScriptService.Modules.CooldownPolicy)

-- o chefe rouba a Ultimate do player, com o cooldown que ela tinha
chefe.EquipSkill(Intents.Id.Ultimate, Keys.Schema.Ultimate, "Roubo")
CooldownPolicy.Transfer(player, chefe, "Schema_Ultimate", "Move")
`,
    desc: `O código acima equipa no chefe a skill roubada (numa camada própria) e leva junto o estado do cooldown dela: se faltavam 6 s para o player, faltam 6 s para o chefe. Com <code>"Move"</code>, a skill do player fica pronta; com <code>"Copy"</code> (padrão), os dois ficam iguais. As duas entidades precisam de Combat.`,
  });

  X("api.CooldownPolicy.Validate", {
    code: `
-- ferramenta: confere a política de cooldown de todas as skills do banco
local SkillDatabase = require(game.ServerStorage.DataBase.SkillDatabase)

for chave, modulo in SkillDatabase._Registry do
    local skill = require(modulo)
    local _, problemas = CooldownPolicy.Validate(skill.data, skill.callbacks)
    if #problemas > 0 then
        warn(chave, table.concat(problemas, "; "))
    end
end
`,
    desc: `O código acima lista os problemas de política de cooldown de cada skill (cooldown ausente, <code>start</code> inválido, recast não declarado numa skill com <code>onRecast</code>...). <code>Validate</code> não tem efeito colateral nem avisa sozinho: devolve a política resolvida e a lista de problemas.`,
  });

  X("api.CooldownPolicy.EffectiveDuration", {
    code: `
local skill = entity.GetSkillFromSlot(Intents.Id.Ultimate)
local policy = CooldownPolicy.Validate(skill.data, skill.callbacks)
print(CooldownPolicy.EffectiveDuration(entity, policy))
-- cooldown 10 com CooldownReduction 0.2 -> 8
`,
    desc: `O código acima calcula quanto duraria o cooldown da Ultimate se começasse agora, com a redução de cooldown da entidade (stat <code>CooldownReduction</code>, limitado pelo <code>maxReduction</code> da política). Útil para mostrar na HUD o tempo real, ou para um <code>StartCooldown</code> manual com a redução aplicada.`,
  });
})();

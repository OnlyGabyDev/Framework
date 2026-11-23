/* Referência da API: skills (self, formatos, SkillHandler, SkillRunner, CooldownPolicy) */
(function () {
  function S(name, call, desc, args, ret, more) {
    var f = { name: name, title: "self:" + name, call: call, desc: desc, args: args || [], ret: ret };
    for (var k in more || {}) f[k] = more[k];
    DOCS.fn("api.skill", f);
  }

  DOCS.page({
    id: "api.skills",
    parent: "api",
    title: "Skills",
    kw: "skills habilidades api",
    lead: "O que uma skill (ou status) pode chamar em self, os formatos de data, a entrada de input e o cooldown.",
    html: "",
  });

  // ================================================================ self
  DOCS.group({
    id: "api.skill",
    parent: "api.skills",
    title: "self (dentro da skill)",
    kw: "self skill runner métodos dentro da skill callbacks damage applystatus stop fizzle own listen hitbox",
    lead: "Dentro de qualquer callback, self é a instância isolada desta ativação. Os métodos abaixo usam dois-pontos (self:Damage) e têm o runner como fonte.",
    html: `
<h2>Campos</h2>
${T(["Campo", "O quê"], [
  ["<code>self.Entity</code>", "Entidade dona (quem casta; num status, o portador)."],
  ["<code>self.Runner</code>", "O SkillRunner. Passe-o em APIs que pedem runner (SetActionState, Source)."],
  ["<code>self.data</code>", "O data (estático; não escreva)."],
  ["<code>self.counter</code>", "Contador livre (começa em 1). Num status com stackOnSelf, são os stacks."],
  ["<code>self.runtimeDuration</code>", "Escreva para mudar a duração desta ativação."],
  ["<code>self.statusTable</code>", "O StateTable (<code>.Status</code>, <code>.States</code>, <code>.ActionStates</code>, <code>.Enum</code>)."],
  ["<code>self.charLib</code>", "Animações do kit dono da skill (com Animation)."],
  ["<code>self.weapon</code>, <code>self.hitPoint</code>", "Model da arma e o hitOrigin (com Weapon)."],
  ["<code>self.Source</code>", "Num status: o runner que aplicou."],
  ["<code>self.ID</code>", "Num status: o ID desta aplicação."],
  ["<code>self.ComboPayload</code>", "Num marcador de ComboWindow: o payload."],
])}
<p>Variáveis da ativação vão em <code>self.qualquerCoisa</code>. Nunca em local do módulo.</p>`,
  });
  S("Damage", "local ok, dano = self:Damage(target, amount, opts?)",
    "Causa dano com este runner como fonte: DamageMult do dono, OUT.onHit, pipeline do alvo, crédito correto.",
    [["target", "EntityCore", "Alvo."], ["amount", "number", "Dano base."], ["opts", "DamageOptions?", "<code>{ Traits?, Effects?, Hit?, Prescaled?, Inherited? }</code>."]],
    "<code>sucesso, danoReal</code>, ou <code>false, Enum.ChainOutcomes.X</code>.",
    { see: ["conceitos.dano", "api.Combat.ApplyDamage"] });
  S("ApplyStatus", "local id = self:ApplyStatus(status, opts?)",
    "Aplica um status com Source = este runner. <code>opts.Target</code> escolhe a entidade (padrão: a própria).",
    [["status", "{ data, callbacks }", "O status."], ["opts", "table?", "<code>{ Target?, Duration?, ID?, Inherited?, Source? }</code>."]],
    "ID ou <code>nil</code>.", { see: ["api.Status.ApplyStatus"] });
  S("StartHitbox", "self:StartHitbox(duration)", "Liga a hitbox da arma DESTA skill. Os acertos chegam no <code>onHit(self, hit)</code>; sai sozinha no fim do runner.",
    [["duration", "number", "Segundos."]], "<code>boolean</code> (false sem Weapon).",
    { notes: N("<p><code>hit</code> = <code>{ target, position, normal, distance, instance, hitboxName, flags, segment }</code>. Um alvo por sessão: para acertar de novo, StopHitbox e StartHitbox.</p>") });
  S("StopHitbox", "self:StopHitbox()", "Desliga a hitbox desta skill e zera a lista de já acertados.", null, null);
  S("Listen", "local unsubscribe = self:Listen(subscription)", "Inscreve na entidade dona com Owner = este runner: sai sozinha quando a skill termina.",
    [["subscription", "Subscription", "Mesmo formato do Listen."]], "Função <code>unsubscribe()</code>.",
    { see: ["api.EntityCore.Listen"] });
  S("Own", "self:Own(cleanup)", "Registra uma limpeza que roda sozinha no fim (qualquer motivo), antes do onEnd. Chamado depois do fim, roda na hora.",
    [["cleanup", "function", "<code>() -> ()</code>."]], null);
  S("Stop", "self:Stop(cancel?)", "Encerra a skill. Com <code>true</code>, é cancelamento (roda onCancel, que pode recusar).",
    [["cancel", "boolean?", "true = cancel; false/nil = fim normal (motivo stop)."]], null);
  S("Fizzle", "self:Fizzle()", "Desiste do cast (alvo não encontrado, condição falhou). Motivo <code>fizzle</code>: por padrão devolve o cooldown inteiro.", null, null);
  S("CommitCooldown", "self:CommitCooldown()", "Confirma o cooldown numa skill com <code>cooldownPolicy.start = \"Manual\"</code> (uma vez por runner).", null, "<code>boolean</code>.");
  S("GetRemainingTime", "self:GetRemainingTime()", "Segundos até o fim pela duração (no Casting, a duração inteira).", null, "<code>number?</code> (nil sem duração).");
  S("endSkill", "self:endSkill(cancel, reason?)", "Encerra com um motivo explícito.",
    [["cancel", "boolean", "Cancelamento?"], ["reason", "string?", "<code>Enum.EndReasons.X</code> (ou um seu)."]], null);
  S("Recast", "self:Recast(checkOnly?, input?)", "Dispara o onRecast desta skill (o SkillHandler chama no toque seguinte).", null, "<code>boolean</code>.");
  S("TriggerAction", "self:TriggerAction(hitCtx)", "Dispara o onTrigger (ou o data.block). Usado pelo motor no bloqueio e no escudo.", null, "Dano novo, true ou nil.");

  // ================================================================ data da skill
  DOCS.page({
    id: "api.skill.data",
    parent: "api.skills",
    title: "Formato de uma skill",
    kw: "formato skill data callbacks campos cooldown duration casttime maxinstances input requires affects effects block traits tags kit",
    lead: "Os campos que o motor lê em data, e a assinatura de cada callback. Campos que o motor não conhece ficam livres para a skill (speed, damage, range…).",
    html: `
<h2>data</h2>
${T(["Campo", "Tipo", "Padrão", "O quê"], [
  ["<code>cooldown</code>", "number", "—", "Segundos. Obrigatório para skill de input (0 vale)."],
  ["<code>cooldownPolicy</code>", "table", "Enum.CooldownDefaults", "<code>{ start, recast, refund, charges, ignoreReduction, maxReduction }</code> (" + L("conceitos.cooldown") + ")."],
  ["<code>duration</code>", "number?", "nil", "Duração do Running. nil = só termina por Stop/cancel."],
  ["<code>castTime</code>", "number?", "0", "Tempo em Casting antes do Running (onStep só no Running)."],
  ["<code>maxInstances</code>", "number", "1", "Runners vivos ao mesmo tempo. Com 1 e onRecast, o toque seguinte vira recast."],
  ["<code>input</code>", "GestureSpec?", "nil (Press)", "<code>{ Hold = true|s, DoubleTap = true|s, Tap = bool }</code> (" + L("conceitos.input") + ")."],
  ["<code>traits</code>", "{string}", "{}", "Traits da skill (entram em todo hit dela)."],
  ["<code>tags</code>", "table", "—", "Só em status (tags viram permissões)."],
  ["<code>requires</code>", "{string}", "nil", "Componentes sem os quais o motor recusa o cast (motivo refused, cooldown devolvido)."],
  ["<code>affects</code>", "table", "Enum.AffectsDefaults", "<code>{ Self, Ally, Enemy, Neutral }</code>: quem a hitbox/zona entrega."],
  ["<code>effects</code>", "{status | table}", "nil", "Status on-hit aplicados em todo hit da skill: <code>{ Status.Bleed, { status = X, onBlocked = true } }</code>."],
  ["<code>effectPolicy</code>", "table", "Enum.EffectDefaults", "<code>{ onBlocked, onZeroDamage }</code> para os efeitos desta skill."],
  ["<code>block</code>", "table", "nil", "Só em status de bloqueio: <code>{ mode, value }</code>."],
  ["<code>kit</code>", "string", "pasta no SkillDatabase", "Kit dono (animações). Skill em código pode declarar."],
  ["<code>name</code>", "string", "chave do banco", "Nome (carimbado pelo EquipSkill)."],
  ["<code>type</code>", "string", "Skill", "Tipo do runner (<code>Enum.Types</code>)."],
])}

<h2>callbacks</h2>
${T(["Callback", "Assinatura", "Quando"], [
  ["<code>onStart</code>", "<code>(self, ctx)</code>", "No start. Erro encerra (motivo error)."],
  ["<code>onStep</code>", "<code>(self, dt, ctx)</code>", "Cada frame do Running. Erro encerra."],
  ["<code>onHit</code>", "<code>(self, hit, ctx)</code>", "Acerto da hitbox da arma desta skill."],
  ["<code>onRecast</code>", "<code>(self, ctx)</code>", "Toque seguinte com a skill viva (ou novo stack, num status stackOnSelf)."],
  ["<code>onRelease</code>", "<code>(self, ctx)</code>", "Soltou o botão (<code>ctx.input.HeldTime</code>)."],
  ["<code>onTrigger</code>", "<code>(self, hitCtx, ctx)</code>", "Num status de bloqueio/escudo: decide o bloqueio. Devolve o dano novo, true (barra status) ou nil."],
  ["<code>onCancel</code>", "<code>(self, ctx)</code>", "Antes do fim num cancelamento. <code>return false</code> recusa (só skill)."],
  ["<code>onEnd</code>", "<code>(self, ctx)</code>", "Sempre, em qualquer fim, com <code>ctx.reason</code>."],
])}

<h2>Esqueleto</h2>
${C(`
local StateTable = require(game.ServerStorage.Modules.Combat.StateTable)
local Component = require(game.ServerScriptService.EntityData.ComponentsExport)
local Enum = StateTable.Enum

return {
    data = {
        cooldown = 4,
        duration = 0.8,
        castTime = 0.15,
        traits = { Enum.Traits.Melee },
        requires = { Component.Weapon },
        effects = { StateTable.Status.Bleed },
        damage = 18,                      -- campo livre da skill
    },
    callbacks = {
        onStart = function(self, ctx)
            self.Entity.SetActionState(self.statusTable.ActionStates.Out.cast, self.Runner)
            self:StartHitbox(self.data.duration)
        end,
        onHit = function(self, hit)
            self:Damage(hit.target, self.data.damage, { Hit = hit })
        end,
        onEnd = function(self, ctx)
            -- limpeza única (ActionState e hitbox já saem sozinhos com o runner)
        end,
    },
}
`)}
`,
  });

  DOCS.page({
    id: "api.skill.statusdata",
    parent: "api.skills",
    title: "Formato de um status",
    kw: "formato status estado data campos stack stackonself maxstacks refreshonmax exclusive category tags bypassby shieldsfrom allowondead cooldown tickrate",
    lead: "Status e estados usam o mesmo formato { data, callbacks } da skill, com campos próprios de aplicação.",
    html: `
${T(["Campo", "Tipo", "O quê"], [
  ["<code>name</code>", "string", "Obrigatório. Chave de GetStatus/RemoveStatus e do stack."],
  ["<code>category</code>", "string", "<code>Enum.Categories</code> (Buff, Debuff, Hybrid, Internal) ou <code>Enum.States</code> nos estados."],
  ["<code>duration</code>", "number?", "Duração padrão (o Duration do ApplyStatus vence). Sem nenhum: dura até ser removido."],
  ["<code>tags</code>", "table", "Permissões que o status liga/desliga (" + L("enum.tags", "Enum.Tags") + ")."],
  ["<code>traits</code>", "{string}", "Stackable, DOT, BlockBreak… e as suas."],
  ["<code>stackOnSelf</code>", "boolean", "Com Stackable: stacks na mesma instância (counter)."],
  ["<code>maxStacks</code>", "number", "Teto de stacks/instâncias."],
  ["<code>refreshOnMax</code>", "boolean", "Padrão true: no teto, a reaplicação renova a duração. false: ignora."],
  ["<code>exclusive</code>", "boolean", "Remove os outros da mesma category ao entrar."],
  ["<code>cooldown</code>", "number", "Cooldown de reaplicação (por nome, na entidade)."],
  ["<code>allowOnDead</code>", "boolean", "Entra mesmo em entidade morta."],
  ["<code>bypassBy</code>", "{string}", "Com uma tag de imunidade: traits que furam (iFrame: TrueHit)."],
  ["<code>ShieldsFrom</code>", "{string}", "Escudo de status: barra status cuja categoria, trait ou nome está na lista (\"All\" = todos). Num bloqueio de dano, filtra por trait."],
  ["<code>ShieldsFromType</code>", "{string}", "Bloqueio só contra fontes deste tipo (<code>Enum.Types.Skill</code>)."],
  ["<code>block</code>", "table", "<code>{ mode = Enum.BlockModes.X, value? }</code> para a tag block."],
  ["campos livres", "any", "tickRate, damage, slow…: o status lê em <code>self.data</code>."],
])}
${C(`
-- StateTable/Status/Buffs/Muralha.luau: bloqueia 60% de dano de skill por 3 s, não quebra
local Enum = require(script.Parent.Parent.Parent.Enum)
return {
    data = {
        name = "Muralha", category = Enum.Categories.Buff, duration = 3,
        tags = { [Enum.Tags.block] = true },
        block = { mode = Enum.BlockModes.Percent, value = 0.6 },
        ShieldsFromType = { Enum.Types.Skill },
        traits = { Enum.Traits.Unbreakable },
    },
    callbacks = {},
}
`)}
<p>Callbacks iguais aos da skill; <code>onRecast</code> roda a cada novo stack (stackOnSelf) e o retorno do <code>onCancel</code> é ignorado.</p>
`,
  });

  // ================================================================ SkillHandler
  DOCS.group({
    id: "api.SkillHandler",
    parent: "api.skills",
    title: "SkillHandler",
    kw: "skillhandler handleintent input npc ia intent movimento look",
    src: "ServerScriptService/Modules/SkillHandler",
    lead: "Entrada única de input do servidor. Player (pelo InputValidator), NPC e scripts de jogo chamam as mesmas funções.",
    html: C(`local SkillHandler = require(game.ServerScriptService.Modules.SkillHandler)`),
  });
  DOCS.fn("api.SkillHandler", {
    name: "HandleIntent", title: "SkillHandler.HandleIntent",
    call: "local ok, skillName, cooldown = SkillHandler.HandleIntent(id, event)",
    desc: "Ativa, faz recast ou entrega o Release da skill do slot da intent. Faz todas as checagens (canCast, morto, maxInstances, recast, cooldown, ActionState).",
    args: [["id", "string", "ID da entidade."], ["event", "InputEvent", "De <code>Intents.NewEvent</code>."]],
    ret: "<code>sucesso</code>; em Activate, também o nome da skill e o cooldown.",
    see: ["conceitos.skills", "api.Intents.NewEvent"],
  });
  DOCS.fn("api.SkillHandler", {
    name: "HandleMovementInput", title: "SkillHandler.HandleMovementInput",
    call: "SkillHandler.HandleMovementInput(id, direction)",
    desc: "Direção de movimento da entidade (achatada no plano). Vai também para as entidades linkadas com MirrorMovement.",
    args: [["id", "string", "ID."], ["direction", "Vector3", "Direção (o tamanho não importa: é normalizada)."]],
    ret: "<code>boolean</code>: a entidade ficou andando (false com direção nula, ID inválido ou valor que não é Vector3).",
  });
  DOCS.fn("api.SkillHandler", {
    name: "HandleLookInput", title: "SkillHandler.HandleLookInput",
    call: "SkillHandler.HandleLookInput(id, look)",
    desc: "Direção de mira/câmera (3D; a LookDirection plana é derivada).",
    args: [["id", "string", "ID."], ["look", "Vector3", "Mira."]],
    ret: "<code>boolean</code>: aplicou (false com vetor quase nulo, ID inválido ou valor que não é Vector3).",
  });
  DOCS.fn("api.SkillHandler", {
    name: "GetGestureSpec", title: "SkillHandler.GetGestureSpec",
    call: "SkillHandler.GetGestureSpec(entity, intent)",
    desc: "Os gestos que a skill do slot declarou em data.input (o InputValidator usa para configurar o GestureResolver).",
    args: [["entity", "EntityCore", ""], ["intent", "string", ""]],
    ret: "GestureSpec ou <code>nil</code>.",
  });

  // ================================================================ SkillRunner
  DOCS.group({
    id: "api.SkillRunner",
    parent: "api.skills",
    title: "SkillRunner",
    kw: "skillrunner runner ciclo de vida new start buildcontext lineage",
    src: "ServerScriptService/Modules/SkillRunner",
    lead: "O ciclo de vida de uma ativação (skill ou status): Idle → Casting → Running → Ended. Normalmente você não cria runners à mão; o SkillHandler e o StatusComponent criam.",
    html: `
${T(["Campo", "O quê"], [
  ["<code>runner.skill</code>", "A instância isolada (o self dos callbacks)."],
  ["<code>runner.Entity</code>", "Entidade dona."],
  ["<code>runner.skillName</code>", "Nome."],
  ["<code>runner.type</code>", "Skill ou Status."],
  ["<code>runner.state</code>", "Idle, Casting, Running, Ended."],
  ["<code>runner.elapsedTime</code>", "Tempo no estado atual."],
  ["<code>runner.Lineage</code>", "Nó da cadeia (Depth, Root, Origin, Parent)."],
  ["<code>runner.Source</code>", "Num status: quem aplicou."],
  ["<code>runner.data</code>", "O data."],
])}`,
  });
  DOCS.fn("api.SkillRunner", {
    name: "new", title: "SkillRunner.new",
    call: "local runner = SkillRunner.new(skillModule, entity, name, type, parentLineage?, input?, inherited?)",
    desc: "Cria um runner sem iniciar. Para uma skill criada por outra skill (cadeia assíncrona com inherited).",
    args: [
      ["skillModule", "table", "<code>{ data, callbacks }</code> (passe por <code>SkillFactory.GetSkill</code> para ganhar os padrões)."],
      ["entity", "EntityCore", "Dona."], ["name", "string", "Nome."], ["type", "string", "<code>Enum.Types.Skill</code> ou Status."],
      ["parentLineage", "Lineage?", "<code>self.Runner.Lineage</code> para virar filho (crédito e limite de cadeia)."],
      ["input", "InputEvent?", ""], ["inherited", "table?", "Payload para <code>ctx.inherited</code> do filho."],
    ],
    ret: "O runner.",
  });
  DOCS.fn("api.SkillRunner", { name: "start", title: "runner:start", call: "runner:start()", desc: "Registra e inicia. Recusa sem os <code>requires</code> ou com a cadeia larga demais.", ret: "<code>false</code> se o onStart falhou ou o motor recusou." });
  DOCS.fn("api.SkillRunner", { name: "BuildContext", title: "runner:BuildContext", call: "runner:BuildContext(forListeners?)", desc: "Monta o RunnerContext (depth, history, rootOrigin, sourceRunner, input, inherited).", ret: "RunnerContext." });
  DOCS.fn("api.SkillRunner", { name: "IsEnded", title: "runner:IsEnded", call: "runner:IsEnded()", desc: "Já terminou?", ret: "<code>boolean</code>." });
  DOCS.fn("api.SkillRunner", { name: "Abort", title: "runner:Abort", call: "runner:Abort()", desc: "Encerra por erro: tenta o cancel e, se recusado, encerra mesmo assim." });
  DOCS.fn("api.SkillRunner", { name: "Release", title: "runner:Release", call: "runner:Release(input)", desc: "Entrega o Release do botão (roda onRelease, se houver).", ret: "<code>boolean</code>." });

  // ================================================================ CooldownPolicy
  DOCS.group({
    id: "api.CooldownPolicy",
    parent: "api.skills",
    title: "CooldownPolicy",
    kw: "cooldownpolicy cooldown transfer herança roubar validar",
    src: "ServerScriptService/Modules/CooldownPolicy",
    lead: "As regras de cooldown. Quase tudo roda sozinho a partir do data; estas são as funções úteis ao jogo.",
    html: C(`local CooldownPolicy = require(game.ServerScriptService.Modules.CooldownPolicy)`),
  });
  DOCS.fn("api.CooldownPolicy", {
    name: "Transfer", title: "CooldownPolicy.Transfer",
    call: "CooldownPolicy.Transfer(from, to, skillName, mode?)",
    desc: "Copia o estado de cooldown de uma skill entre entidades (tempo restante e cargas). Para skill roubada e possessão.",
    args: [["from", "EntityCore", "Origem (com Combat)."], ["to", "EntityCore", "Destino (com Combat)."], ["skillName", "string", "Nome."], ["mode", "string?", "\"Copy\" (padrão) ou \"Move\" (a origem fica pronta)."]],
    ret: "<code>boolean</code>.",
    see: ["receitas.roubar"],
  });
  DOCS.fn("api.CooldownPolicy", {
    name: "Validate", title: "CooldownPolicy.Validate",
    call: "local policy, issues = CooldownPolicy.Validate(data, callbacks)",
    desc: "Lê e valida a política declarada, sem efeito colateral (útil em ferramenta de checagem).",
    ret: "<code>policy</code> resolvida e a lista de problemas.",
  });
  DOCS.fn("api.CooldownPolicy", {
    name: "EffectiveDuration", title: "CooldownPolicy.EffectiveDuration",
    call: "CooldownPolicy.EffectiveDuration(entity, policy)",
    desc: "Duração de uma contagem que começasse agora: cooldown × (1 − CooldownReduction), com o teto da skill.",
    ret: "<code>number</code>.",
  });
})();

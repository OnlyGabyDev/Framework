/* Referência da API: componentes (funções expostas na entidade) */
(function () {
  function F(group, name, call, desc, args, ret, more) {
    var f = { name: name, title: "entity." + name, call: call, desc: desc, args: args || [], ret: ret };
    for (var k in more || {}) f[k] = more[k];
    DOCS.fn(group, f);
  }

  DOCS.page({
    id: "api.componentes",
    parent: "api",
    title: "Componentes",
    kw: "componentes components api entidade",
    lead: "A API de cada componente, chamada na entidade com ponto: entity.Função(...). Config é a tabela passada no DataManager.Create em configs[NomeDoComponente].",
    html: "",
  });

  // ================================================================ Character
  DOCS.group({
    id: "api.Character", parent: "api.componentes", title: "Character",
    kw: "character personagem model modelo root humanoid posição teleporte corpo",
    src: "ServerScriptService/EntityData/Components/CharacterComponent",
    lead: "O corpo da entidade: Model, root (HumanoidRootPart ou PrimaryPart) e Humanoid. Base de Movement, Weapon e Animation. NPC com Humanoid anda pelo Humanoid; sem Humanoid, pelo ForceRig.",
    html: "<p>Config: nenhum. O DataManager entrega o Model sozinho.</p>",
  });
  var G = "api.Character";
  F(G, "GetModel", "entity.GetModel()", "O Model da entidade.", null, "<code>Model</code>.");
  F(G, "GetRoot", "entity.GetRoot()", "A peça raiz (HumanoidRootPart, ou PrimaryPart).", null, "<code>BasePart</code>.",
    { ex: "local release = alvo.AttachTo(self.Entity.GetRoot(), CFrame.new(0, 0, -4))" });
  F(G, "GetHumanoid", "entity.GetHumanoid()", "O Humanoid, se houver.", null, "<code>Humanoid?</code>.");
  F(G, "GetPosition", "entity.GetPosition()", "Posição do root.", null, "<code>Vector3</code>.",
    { ex: "local dist = (alvo.GetPosition() - self.Entity.GetPosition()).Magnitude" });
  F(G, "GetCFrame", "entity.GetCFrame()", "CFrame do root.", null, "<code>CFrame</code>.");
  F(G, "Teleport", "entity.Teleport(position)", "Teleporta o root para a posição (pelo servidor: o anti-cheat abre a janela de confiança).",
    [["position", "Vector3", "Destino."]], null);
  F(G, "GetCharacterWrapper", "entity.GetCharacterWrapper()", "O wrapper de corpo (abstração Humanoid × rig sem Humanoid).", null, "Wrapper.");
  F(G, "SetEntity", "entity.SetEntity(model | { Model, Player })", "Liga o corpo. Chamado pelo DataManager; raramente usado à mão.", null, "<code>boolean</code>.");

  // ================================================================ Health
  DOCS.group({
    id: "api.Health", parent: "api.componentes", title: "Health",
    kw: "health vida hp dano damage cura heal morte death revive maxhp sobrevida",
    src: "ServerScriptService/EntityData/Components/HealthComponent",
    lead: "Vida, dano do lado do alvo, cura com teto declarado, morte e revive. HP acima do MaxHP é permitido.",
    html: `
${T(["Config", "Tipo", "Padrão", "O quê"], [
  ["<code>MaxHP</code>", "number", "Enum.StatDefaults.MaxHP (100)", "Teto. Com Attributes, o MaxHP vem do stat."],
  ["<code>StartHP</code>", "number", "MaxHP", "HP inicial (pode passar do MaxHP)."],
  ["<code>HealCap</code>", "number", "Enum.HealthDefaults.HealCap (1)", "Teto da cura em × MaxHP."],
  ["<code>Events</code>", "table", "—", "<code>{ onDamage, onHeal, onDeath, onRevive }</code>: atalhos para os eventos IN (onDamage = PostDamage)."],
])}
<p>Veja ${L("conceitos.dano")}, ${L("conceitos.cura")} e ${L("conceitos.morte")}.</p>`,
  });
  G = "api.Health";
  F(G, "TakeDamage", "local ok, dano, ctx = entity.TakeDamage(amountOrContext, source?)",
    "Aplica dano nesta entidade pelo pipeline do alvo (imunidade, bloqueio, proteções, PreDamage, HP, efeitos on-hit, PostDamage, OnDamage no dono). Para dano de skill, prefira <code>self:Damage</code>, que passa pelo lado do atacante também.",
    [["amountOrContext", "number | HitContext", "Dano base, ou um contexto pronto."], ["source", "runner?", "Quem causou (crédito, traits, cadeia)."]],
    "<code>true, danoReal, ctx</code>; ou <code>false, motivo</code> (imunidade, cancelado, morto, ou <code>Enum.ChainOutcomes.Deferred</code>).",
    { ex: "-- dano de ambiente (lava), sem fonte\nentity.TakeDamage(5)\n-- dano de um status (o runner do status é a fonte)\nself.Entity.TakeDamage(self.data.damage, self.Runner)", see: ["api.skill.Damage", "conceitos.dano"] });
  F(G, "Heal", "local subiu = entity.Heal(amount, opts?)",
    "Cura até <code>Cap × MaxHP</code>, nunca reduzindo o HP (sobrevida fica). Emite IN.OnHeal (antes) e, com Source, OUT.OnHeal no dono.",
    [["amount", "number", "Quanto curar."], ["opts", "HealOptions?", "<code>{ Source = runner?, Traits = {string}?, Cap = number? }</code>."]],
    "Quanto o HP subiu (<code>number</code>).",
    { ex: "local subiu = aliado.Heal(30, { Source = self.Runner, Cap = 1.25 })", see: ["conceitos.cura", "receitas.lifesteal"] });
  F(G, "Die", "entity.Die(killer?)", "Mata a entidade (HP 0): IN.OnDeath nela e OUT.OnDeath no dono do killer.",
    [["killer", "runner?", "Quem matou (crédito)."]], null, { see: ["conceitos.morte"] });
  F(G, "Revive", "entity.Revive(hp?)", "Revive com exatamente <code>hp</code> (ou o MaxHP). Emite IN.OnRevive.",
    [["hp", "number?", "HP de volta (sem corte no MaxHP)."]], "<code>boolean</code> (false se não estava morta).");
  F(G, "GetHP", "entity.GetHP()", "HP atual.", null, "<code>number</code>.");
  F(G, "GetMaxHP", "entity.GetMaxHP()", "MaxHP (com Attributes, inclui modificadores).", null, "<code>number</code>.");
  F(G, "SetHP", "entity.SetHP(value)", "Define o HP exato, sem corte no MaxHP. Só não fica negativo; 0 ou menos mata. Subir emite IN.OnHeal.",
    [["value", "number", "Novo HP."]], null);
  F(G, "SetMaxHP", "entity.SetMaxHP(value)", "Troca o teto mantendo a proporção do HP (com Attributes, grava o stat).",
    [["value", "number", "Novo MaxHP (mínimo 1)."]], null);
  F(G, "GetHealthRatio", "entity.GetHealthRatio()", "HP / MaxHP.", null, "<code>number</code> (pode passar de 1).");
  F(G, "IsAlive", "entity.IsAlive()", "Está viva?", null, "<code>boolean</code>.");
  F(G, "GetDamageHistory", "entity.GetDamageHistory()", "Os últimos 10 danos recebidos, do mais novo ao mais velho: <code>{ amount, source, time }</code>.", null, "<code>table</code>.");
  F(G, "GetTotalDamageTaken", "entity.GetTotalDamageTaken()", "Soma do histórico (os últimos 10 danos, não a vida inteira).", null, "<code>number</code>.");
  F(G, "SyncHealthHUD", "entity.SyncHealthHUD()", "Reenvia a barra de vida a quem dirige o corpo.", null, null);

  // ================================================================ Status
  DOCS.group({
    id: "api.Status", parent: "api.componentes", title: "Status",
    kw: "status statuscomponent buff debuff estado stun aplicar remover tags imunidade bloqueio",
    src: "ServerScriptService/EntityData/Components/StatusComponent",
    lead: "Status e estados da entidade. Cada um é um runner; as tags dos ativos viram as permissões da entidade.",
    html: `<p>Config: <code>RefuseStatusOnDeath</code> (padrão em Enum.DeathDefaults). Veja ${L("conceitos.status")} e o formato em ${L("api.skill.statusdata")}.</p>`,
  });
  G = "api.Status";
  F(G, "ApplyStatus", "local id = entity.ApplyStatus(status, opts | duration)",
    "Aplica um status NESTA entidade. Para mirar outra entidade de dentro de uma skill, use <code>self:ApplyStatus(status, { Target = alvo })</code>.",
    [["status", "{ data, callbacks }", "O módulo do status (<code>StateTable.Status.X</code>, <code>StateTable.States.X</code>) ou uma tabela."],
     ["opts", "table | number", "<code>{ Duration?, Source?, ID?, Inherited? }</code>, ou só a duração."]],
    "O ID da aplicação, ou <code>nil</code> se não entrou (morto, escudo, cancelado no PreApplyStatus, em cooldown, no teto, ou adiado pela cadeia).",
    { ex: "local id = entity.ApplyStatus(StateTable.States.Root, { Duration = 2, Source = runner })\n-- ...\nentity.RemoveStatusByID(id)", see: ["api.skill.ApplyStatus", "conceitos.status"] });
  F(G, "RemoveStatusByID", "entity.RemoveStatusByID(id)", "Remove a aplicação com este ID (todas as entradas dele). É a forma recomendada.",
    [["id", "string", "O ID que o ApplyStatus devolveu."]], "<code>boolean</code>.");
  F(G, "RemoveStatus", "entity.RemoveStatus(name)", "Remove TODAS as instâncias do status com este nome (nos dois grupos).",
    [["name", "string", "<code>data.name</code> do status."]], "<code>boolean</code> (removeu alguma).");
  F(G, "RemoveAmount", "entity.RemoveAmount(name, amount)", "Tira <code>amount</code> stacks/instâncias de um status empilhável.",
    [["name", "string", "Nome."], ["amount", "number", "Quantos."]], null);
  F(G, "GetStatus", "entity.GetStatus(name)", "As entradas ativas do status (<code>{ data, runner, sourceSkill, ID }</code>).",
    [["name", "string", "Nome."]], "<code>table?</code>.", { ex: "local e = alvo.GetStatus(\"Bleed\")\nif e then print(e[1].runner.skill.counter) end" });
  F(G, "GetStatusCounter", "entity.GetStatusCounter(name)", "Stacks do status (o counter da instância, ou o número de instâncias).",
    [["name", "string", "Nome."]], "<code>number</code>.");
  F(G, "GetActiveTags", "local tags, donos = entity.GetActiveTags()", "Tags combinadas de todos os status ativos (false vence) e o dono de cada tag (aplicação mais recente).",
    null, "<code>{ [tag]: boolean }</code>, <code>{ [tag]: entrada }</code>.",
    { ex: "if entity.GetActiveTags()[Enum.Tags.canMove] == false then return end", see: ["conceitos.tags"] });
  F(G, "GetActiveStates", "entity.GetActiveStates()", "Estados ativos (Stun, Root…).", null, "<code>{ [nome]: entrada }</code>.");
  F(G, "HasStateCategory", "entity.HasStateCategory(category)", "Algum estado ativo desta categoria?",
    [["category", "string", "Ex.: <code>Enum.States.Stun</code>."]], "<code>boolean</code>.");
  F(G, "ValidateHit", "entity.ValidateHit(ctx)", "Imunidade: o hit pode afetar a entidade? (usado pelo TakeDamage)",
    [["ctx", "HitContext", "Contexto com traits."]], "<code>boolean</code>, motivo (a tag que barrou).");
  F(G, "ApplyMitigation", "entity.ApplyMitigation(ctx)", "Bloqueio: com a tag block, reduz/zera <code>ctx.damage</code> pelo status dono (usado pelo TakeDamage).",
    [["ctx", "HitContext", "Contexto."]], null);
  F(G, "GetImmunityRules", "entity.GetImmunityRules()", "Mapa de imunidades (tag → traits que furam), calculado uma vez para o servidor.", null, "<code>table</code>.");
  F(G, "GenerateUniqueEffectID", "entity.GenerateUniqueEffectID(name?)", "Gera um ID único de aplicação.", [["name", "string?", "Prefixo."]], "<code>string</code>.");
  F(G, "HasStatusCooldown", "entity.HasStatusCooldown(name)", "O status está em cooldown de reaplicação (<code>data.cooldown</code>)?", [["name", "string", "Nome."]], "<code>boolean</code>.");
  F(G, "SetStatusCooldown", "entity.SetStatusCooldown(name, duration)", "Põe o status em cooldown de reaplicação.", [["name", "string", "Nome."], ["duration", "number", "Segundos."]], null);
  F(G, "GetStatusCooldown", "entity.GetStatusCooldown(name)", "Segundos restantes do cooldown de reaplicação.", [["name", "string", "Nome."]], "<code>number</code>.");

  // ================================================================ Combat
  DOCS.group({
    id: "api.Combat", parent: "api.componentes", title: "Combat",
    kw: "combat combate loadout skill slot equipar cooldown dano applydamage personagem forma actionstate interromper",
    src: "ServerScriptService/EntityData/Components/CombatComponent",
    lead: "Loadout em camadas, cooldowns, skills ativas, ActionState e o lado do atacante no dano. Sem Combat, a entidade não casta skills por input.",
    html: `
${T(["Config", "Padrão", "O quê"], [
  ["<code>ChosenChar</code>", "Enum.CombatDefaults.ChosenChar", "Kit do CharacterDatabase. <code>false</code> = sem personagem (loadout vazio)."],
  ["<code>Mode</code>", "Enum.CombatDefaults.Mode (Base)", "Forma inicial."],
  ["<code>CancelSkillsOnDeath</code>", "true", "A morte cancela as skills ativas."],
  ["<code>RefuseCastOnDeath</code>", "true", "Morto não casta."],
])}
<p>Veja ${L("conceitos.loadout")}, ${L("conceitos.cooldown")} e ${L("conceitos.actionstates")}.</p>`,
  });
  G = "api.Combat";
  F(G, "ApplyLoadout", "entity.ApplyLoadout(loadout, layer?)", "Troca uma camada inteira do loadout (padrão Base).",
    [["loadout", "table", "<code>{ Slots = { [Intents.Id] = chave | skill | false } }</code> ou <code>{ List = { chave, ... } }</code>."], ["layer", "string?", "Nome da camada."]],
    null, { ex: "entity.ApplyLoadout({ Slots = { [Intents.Id.Ultimate] = Keys.Schema.Ultimate } }, \"Desperto\")", see: ["conceitos.loadout"] });
  F(G, "EquipSkill", "entity.EquipSkill(slot, skill, layer?)", "Equipa uma skill num slot da camada (padrão Base). Carimba <code>data.name</code> e <code>data.kit</code> da skill do banco.",
    [["slot", "string", "<code>Intents.Id.X</code>."], ["skill", "string | table", "Chave do SkillDatabase ou uma tabela de skill."], ["layer", "string?", "Camada."]],
    "<code>boolean</code>.", { ex: "entity.EquipSkill(Intents.Id.Ability2, Keys.Schema.Skill3)\n-- skill criada em código\nentity.EquipSkill(Intents.Id.Ability3, { data = { cooldown = 1, duration = 0.2 }, callbacks = { onStart = function(self) end } })" });
  F(G, "AddSkill", "entity.AddSkill(skill, layer?)", "Equipa no próximo slot livre da camada, na ordem de <code>Intents.SkillOrder</code>.",
    [["skill", "string | table", "Chave ou tabela."], ["layer", "string?", "Camada."]], "O slot usado, ou <code>nil</code> (cheio).");
  F(G, "UnequipSlot", "entity.UnequipSlot(slot, layer?)", "Tira a skill do slot nesta camada (a de baixo volta a valer).", [["slot", "string", "Intent."], ["layer", "string?", "Camada."]], null);
  F(G, "RemoveLoadoutLayer", "entity.RemoveLoadoutLayer(layer)", "Tira uma camada (a Base não sai).", [["layer", "string", "Camada."]], "<code>boolean</code>.");
  F(G, "GetLoadoutLayers", "entity.GetLoadoutLayers()", "Nomes das camadas, de baixo para cima.", null, "<code>{string}</code>.");
  F(G, "GetSkillFromSlot", "entity.GetSkillFromSlot(slot)", "A skill efetiva no slot.", [["slot", "string", "Intent."]], "Tabela da skill ou <code>nil</code>.");
  F(G, "GetChosenChar", "entity.GetChosenChar()", "O kit atual.", null, "<code>string?</code>.");
  F(G, "GetCharMode", "entity.GetCharMode()", "A forma atual.", null, "<code>string</code>.");
  F(G, "SetCharMode", "entity.SetCharMode(kit, mode)", "Troca personagem/forma: aplica os Stats (Speed, JumpForce e os demais no Attributes; MaxHP mantendo a proporção) e o Loadout da forma na camada Base.",
    [["kit", "string", "Pasta do CharacterDatabase."], ["mode", "string", "Módulo da forma."]], "<code>true</code>, ou warn.",
    { notes: N("<p>Na troca em runtime, os Stats da forma viram a base do Attributes (MaxHP pelo SetMaxHP). Stat que a forma nova não declara fica como estava. Na criação, o <code>BaseStats</code> do config do Attributes continua valendo.</p>") });
  F(G, "HasCooldown", "entity.HasCooldown(skillName)", "A skill está em cooldown (com cargas: sem nenhuma)?", [["skillName", "string", "<code>data.name</code>."]], "<code>boolean</code>.");
  F(G, "GetCooldown", "entity.GetCooldown(skillName)", "Segundos restantes (com cargas: 0 enquanto houver carga).", [["skillName", "string", "Nome."]], "<code>number</code>.");
  F(G, "SetCooldown", "entity.SetCooldown(skillName, seconds?)", "Define o tempo restante (sem segundos: o cooldown do módulo).", [["skillName", "string", "Nome."], ["seconds", "number?", "Segundos."]], null);
  F(G, "StartCooldown", "entity.StartCooldown(skillName, duration, maxCharges?)", "Inicia uma contagem (ou gasta uma carga). O CooldownPolicy usa no cast; scripts podem chamar.",
    [["skillName", "string", "Nome."], ["duration", "number", "Segundos."], ["maxCharges", "number?", "Cargas."]], null);
  F(G, "ReduceCooldown", "entity.ReduceCooldown(skillName, seconds)", "Encurta a contagem corrente (redução pontual: on-hit, on-kill).",
    [["skillName", "string", "Nome."], ["seconds", "number", "Segundos."]], null, { ex: "-- on-kill: -2 s na ultimate\nself:Listen({ Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.OnDeath,\n    Action = function() self.Entity.ReduceCooldown(\"Schema_Ultimate\", 2) end })" });
  F(G, "GrantCooldownCharge", "entity.GrantCooldownCharge(skillName)", "Devolve uma carga (sem cargas: fica pronta).", [["skillName", "string", "Nome."]], null);
  F(G, "GetCooldownCharges", "entity.GetCooldownCharges(skillName)", "Cargas disponíveis e máximo.", [["skillName", "string", "Nome."]], "<code>number?, number?</code> (nil se a skill não usa cargas).");
  F(G, "ExportCooldown", "entity.ExportCooldown(skillName)", "Estado relativo, para copiar entre entidades.", [["skillName", "string", "Nome."]], "<code>{ remaining, duration, charges?, maxCharges? }</code> ou <code>nil</code> (pronta).");
  F(G, "ImportCooldown", "entity.ImportCooldown(skillName, snapshot)", "Aplica um estado exportado.", [["skillName", "string", "Nome."], ["snapshot", "table?", "De ExportCooldown (nil = pronta)."]], null,
    { see: ["api.CooldownPolicy.Transfer"] });
  F(G, "ResetCooldown", "entity.ResetCooldown(skillName)", "Pronta de novo (com cargas: todas).", [["skillName", "string", "Nome."]], null);
  F(G, "ResetAllCooldowns", "entity.ResetAllCooldowns()", "Todas as skills prontas.", null, null);
  F(G, "GetActiveSkills", "entity.GetActiveSkills(skillName?)", "Runners ativos de uma skill, ou o mapa de todas.", [["skillName", "string?", "Nome."]], "<code>{runner}</code> ou <code>{ [nome]: {runner} }</code>.");
  F(G, "GetActiveSkillCount", "entity.GetActiveSkillCount(skillName)", "Quantos runners vivos da skill.", [["skillName", "string", "Nome."]], "<code>number</code>.");
  F(G, "HasActiveSkill", "entity.HasActiveSkill(skillName)", "A skill está rodando?", [["skillName", "string", "Nome."]], "<code>boolean</code>.");
  F(G, "StopAllActiveSkills", "entity.StopAllActiveSkills(cancel?, runnerType?)", "Para todas as skills ativas (quem recusa o cancel segue viva).",
    [["cancel", "boolean?", "true = cancelamento (roda onCancel)."], ["runnerType", "string?", "Só deste tipo (<code>Enum.Types</code>)."]], null);
  F(G, "InterruptSkills", "entity.InterruptSkills()", "Cancela as skills ativas com o motivo <code>interrupted</code>, menos as <code>Uninterruptible</code>. Chamado sozinho quando entra um estado com a tag interrupt.", null, null);
  F(G, "CanContinue", "entity.CanContinue(skill)", "A entidade pode castar agora? (morta, ou tag canCast = false, não)", [["skill", "table", "A skill."]], "<code>boolean</code>.");
  F(G, "TrySelfCancel", "entity.TrySelfCancel()", "Cancela a ação atual se o ActionState for Self.", null, "<code>true</code> se liberou (ou não havia), <code>false</code> se o estado não é Self ou a skill recusou.");
  F(G, "SetActionState", "entity.SetActionState(state, runner)", "Define o ActionState (trava de ação) com o runner dono.",
    [["state", "table", "<code>StateTable.ActionStates.Self.selfCast</code>, <code>.Out.cast</code>, <code>.LockedCast</code>…"], ["runner", "runner | self", "O runner (ou o self da skill)."]], null, { see: ["conceitos.actionstates"] });
  F(G, "GetActionState", "entity.GetActionState()", "O ActionState atual.", null, "<code>{ name, runner }</code> ou <code>nil</code>.");
  F(G, "RemoveActionState", "entity.RemoveActionState(runner?)", "Remove o ActionState (com runner: só se for dele).", [["runner", "runner?", "Dono."]], null);
  F(G, "ApplyDamage", "local ok, dano = entity.ApplyDamage(amount, source, target, opts?)",
    "Dano do lado do atacante: DamageMult, OUT.onHit e o TakeDamage do alvo. É o que <code>self:Damage</code> chama.",
    [["amount", "number", "Dano base."], ["source", "runner", "Runner que causou."], ["target", "EntityCore", "Alvo (precisa de Health)."], ["opts", "DamageOptions?", "<code>{ Traits, Effects, Hit, Prescaled, Inherited }</code>."]],
    "<code>sucesso, danoReal</code> ou <code>false, Enum.ChainOutcomes.X</code>.", { see: ["api.skill.Damage", "conceitos.dano"] });
  F(G, "AddActiveSkill", "entity.AddActiveSkill(skillName, runner)", "Registra um runner como ativo (o motor faz no start).", null, null);
  F(G, "RemoveActiveSkill", "entity.RemoveActiveSkill(skillName, runner)", "Tira o runner das ativas (o motor faz no fim).", null, null);
  F(G, "SetIntentRunner", "entity.SetIntentRunner(intent, runner)", "Interno: guarda o runner que a intent ativou, para o Release chegar nele.", null, null);
  F(G, "TakeIntentRunner", "entity.TakeIntentRunner(intent)", "Interno: devolve e limpa o runner da intent.", null, "runner ou <code>nil</code>.");

  // ================================================================ Attributes
  DOCS.group({
    id: "api.Attributes", parent: "api.componentes", title: "Attributes",
    kw: "attributes atributos stats stat modificador modifier speed defense armor damagemult",
    src: "ServerScriptService/EntityData/Components/AttributesComponent",
    lead: "Stats com base e modificadores por origem, dentro dos limites declarados. InitPriority High: carrega antes dos outros componentes.",
    html: `<p>Config: <code>BaseStats = { [stat] = valor }</code> (sem ele, vem da forma do personagem, ou de Enum.StatDefaults). Veja ${L("conceitos.stats")}.</p>`,
  });
  G = "api.Attributes";
  F(G, "GetStat", "entity.GetStat(stat, default?)", "Valor final do stat: base, modificadores e limite.",
    [["stat", "string", "<code>Enum.Stats.X</code> (ou um nome seu)."], ["default", "any?", "Usado se não há base registrada."]], "O valor.",
    { ex: "local vel = entity.GetStat(Enum.Stats.Speed, Enum.StatDefaults.Speed)" });
  F(G, "SetStat", "entity.SetStat(stat, value)", "Define o valor base.", [["stat", "string", "Stat."], ["value", "any", "Valor."]], null);
  F(G, "GetStats", "entity.GetStats()", "A tabela da forma do personagem (<code>{ Stats, Loadout, Weapon, ... }</code>), ou <code>{ Stats = StatDefaults }</code> sem Combat.", null, "<code>table</code>.");
  F(G, "AddModifier", "entity.AddModifier(stat, sourceID, type, value)", "Adiciona (ou reforça) um modificador com contagem de referência.",
    [["stat", "string", "Stat."], ["sourceID", "any", "ID da origem."], ["type", "string", "<code>Enum.ModifierType</code>: Flat, AddPercent, MultPercent, Override."], ["value", "number", "Valor."]], null,
    { ex: "entity.AddModifier(\"Speed\", zona.ID, \"MultPercent\", 0.6)", see: ["conceitos.stats"] });
  F(G, "RemoveModifier", "entity.RemoveModifier(stat, sourceID)", "Tira UMA referência do modificador (sai de vez com a contagem em zero).",
    [["stat", "string", "Stat."], ["sourceID", "any", "ID da origem."]], null);

  // ================================================================ Movement
  DOCS.group({
    id: "api.Movement", parent: "api.componentes", title: "Movement",
    kw: "movement movimento force força dash knockback direção direction look mira aim attach grab agarrar voo",
    src: "ServerScriptService/EntityData/Components/MovementComponent",
    lead: "Intenção de movimento (direção, mira) e as Forces ativas. Não aplica física: quem aplica é o MovementController. Depende de Character.",
    html: `<p>Config: <code>MassScaling = false</code> (forças e caminhada em números fixos para esta entidade). Veja ${L("conceitos.movimento")}.</p>`,
  });
  G = "api.Movement";
  F(G, "AddForce", "local id = entity.AddForce(force)", "Adiciona uma Force (dash, knockback, vento, voo, tether). Com <code>Key</code> de uma Force ativa, renova a mesma.",
    [["force", "table", "Formato abaixo."]], "ID da Force (<code>string</code>), ou <code>nil</code> se um filtro recusou.",
    { notes: T(["Campo", "Tipo", "O quê"], [
      ["<code>Type</code>", "string", "Rótulo livre."],
      ["<code>Duration</code>", "number", "Segundos."],
      ["<code>Speed</code>", "number | fn(elapsed, duration)", "Velocidade."],
      ["<code>Direction</code>", "Vector3 | fn(elapsed, duration, ctx)", "Direção; ctx = { Entity, MovementComponent }."],
      ["<code>Key</code>", "string?", "Renova a Force ativa de mesma Key."],
      ["<code>Priority</code>", "number?", "Empate de eixo: maior vence (padrão 0)."],
      ["<code>Hard</code>", "boolean?", "true fixa os eixos; false (Soft) soma com a caminhada."],
      ["<code>Axes</code>", "{X,Y,Z}?", "Eixos reivindicados (Hard: todos; Soft: X,Z)."],
      ["<code>IgnoreGravity</code>", "boolean?", "Reivindica o Y."],
      ["<code>RequiresControl</code>", "boolean?", "Padrão true: cancela sem canMove. Externas: false."],
      ["<code>External</code>", "boolean?", "Padrão = not RequiresControl. Barrada por canDisplace = false."],
      ["<code>TurnRate</code>", "number?", "Rad/s para suavizar a direção."],
      ["<code>FaceDirection</code>", "boolean?", "Padrão = Hard: gira o corpo."],
      ["<code>MaxForce</code>", "number?", "Força absoluta."],
      ["<code>Responsiveness</code>", "number?", "Rigidez do ajuste."],
      ["<code>FollowTarget</code>", "BasePart | fn?", "Tether: persegue a peça."],
      ["<code>FollowOffset</code>, <code>FollowOffsetIsLocal</code>", "Vector3?, boolean?", "Offset do alvo (local gira junto)."],
      ["<code>FollowResponsiveness</code>, <code>FollowMaxSpeed</code>, <code>FollowFeedForward</code>", "number?, number?, boolean?", "Ganho, limite e soma da velocidade do líder (padrão true)."],
      ["<code>OnEnd</code>", "fn?", "Chamado no fim da Force."],
    ]),
      ex: "-- knockback: externo, curto, fixo no plano\nalvo.AddForce({\n    Type = \"Knockback\", Duration = 0.25, Speed = 60,\n    Direction = (alvo.GetPosition() - self.Entity.GetPosition()).Unit,\n    Hard = true, RequiresControl = false, Priority = 5,\n})",
      see: ["conceitos.movimento", "api.Movement.RemoveForce"] });
  F(G, "RemoveForce", "entity.RemoveForce(id)", "Remove a Force pelo ID.", [["id", "string", "ID do AddForce."]], null);
  F(G, "RemoveForceByKey", "entity.RemoveForceByKey(key)", "Remove a Force ativa com esta Key.", [["key", "string", "Key."]], "<code>boolean</code>.");
  F(G, "ClearForces", "entity.ClearForces()", "Remove todas as Forces.", null, null);
  F(G, "AttachTo", "local release = entity.AttachTo(leaderPart, offset?, opts?)",
    "Agarrão rígido: um WeldConstraint põe o corpo no assembly do líder, sem atraso (também com líder player). Enquanto preso: Forces e caminhada suspensas, Humanoid em PlatformStand, peças sem massa. Se o líder some, solta sozinho.",
    [["leaderPart", "BasePart", "Peça do líder (ex.: <code>lider.GetRoot()</code>)."], ["offset", "CFrame?", "CFrame deste root no espaço da peça (padrão: onde está)."], ["opts", "table?", "<code>{ Massless = boolean? }</code> (padrão true)."]],
    "Função <code>release()</code> idempotente, ou <code>nil</code>.", { see: ["receitas.agarrao", "api.Movement.Detach"] });
  F(G, "Detach", "entity.Detach()", "Solta o agarrão rígido atual.", null, null);
  F(G, "GetAttachment", "entity.GetAttachment()", "O agarrão atual (cópia).", null, "<code>{ Leader, Offset }</code> ou <code>nil</code>.");
  F(G, "SetDirection", "entity.SetDirection(dir)", "Direção de movimento (input). Players: vem do RequestDir; NPC: do Brain via SkillHandler.HandleMovementInput.", [["dir", "Vector3", "Direção."]], null);
  F(G, "GetDirection", "entity.GetDirection()", "Direção de movimento atual.", null, "<code>Vector3</code>.");
  F(G, "GetLastDirection", "entity.GetLastDirection()", "Última direção não nula.", null, "<code>Vector3</code>.");
  F(G, "GetIntentDirection", "entity.GetIntentDirection()", "Direção pretendida (input) em uso pelo controlador.", null, "<code>Vector3</code>.");
  F(G, "SetAimDirection", "entity.SetAimDirection(dir)", "Mira 3D (câmera). Atualiza a LookDirection plana.", [["dir", "Vector3", "Mira."]], null);
  F(G, "GetAimDirection", "entity.GetAimDirection()", "Mira 3D (com pitch: voo).", null, "<code>Vector3</code>.");
  F(G, "GetLookDirection", "entity.GetLookDirection()", "Direção da câmera no plano (combate).", null, "<code>Vector3</code>.");
  F(G, "GetAirState", "entity.GetAirState()", "Grounded, Jumping, Falling ou Floating (algo suspende o Y de propósito).", null, "<code>string</code>.");
  F(G, "SetSpeed", "entity.SetSpeed(value)", "Velocidade de caminhada direto no wrapper (o MovementController relê o stat Speed a cada frame: para mudança duradoura, use o stat).", [["value", "number", "studs/s."]], null);
  F(G, "SetJumpForce", "entity.SetJumpForce(value)", "Pulo direto no wrapper (mesma ressalva do SetSpeed).", [["value", "number", "Força."]], null);
  F(G, "SetFrozen", "entity.SetFrozen(frozen)", "Congela/descongela o corpo.", [["frozen", "boolean", ""]], null);
  F(G, "AddFilter", "entity.AddFilter(id, fn)", "Filtro de Forces: <code>fn(force)</code> devolvendo <code>false</code> recusa o AddForce.",
    [["id", "any", "ID do filtro."], ["fn", "function", "<code>(force) -> boolean?</code>."]], null,
    { ex: "-- chefe imune a knockback\nchefe.AddFilter(\"SemKnockback\", function(force) return force.Type ~= \"Knockback\" end)" });
  F(G, "RemoveFilter", "entity.RemoveFilter(id)", "Tira um filtro.", [["id", "any", "ID."]], null);
  F(G, "GetForceSpeedBudget", "entity.GetForceSpeedBudget()", "Quanto as Forces deslocam além da caminhada (usado pelo anti-cheat).", null, "horizontal, vertical (studs/s).");
  F(G, "SetDrivesInput", "entity.SetDrivesInput(value)", "Interno: o servidor dirige o corpo (NPC, possessão).", null, null);
  F(G, "SetMovement", "entity.SetMovement()", "Interno: liga o corpo ao MovementController (o DataManager chama).", null, null);
  F(G, "GetMovementWrapper", "entity.GetMovementWrapper()", "O wrapper de movimento (IMovement).", null, "Wrapper.");

  // ================================================================ Weapon
  DOCS.group({
    id: "api.Weapon", parent: "api.componentes", title: "Weapon",
    kw: "weapon arma equipar hitbox modo mode handle hitorigin dual",
    src: "ServerScriptService/EntityData/Components/WeaponComponent",
    lead: "Arma equipada, modos (WeaponData) e a hitbox da arma por skill. A arma inicial vem do stat Weapon (forma do personagem) ou do config.",
    html: `${T(["Config", "O quê"], [
  ["<code>WeaponName</code>", "Arma inicial pelo nome (procurada nos kits)."],
  ["<code>WeaponModel</code>", "Model direto (entidade sem personagem)."],
  ["<code>IsCosmetic</code>", "true = não cria hitbox."],
])}<p>Estrutura do model em ${L("conceitos.personagens")}.</p>`,
  });
  G = "api.Weapon";
  F(G, "EquipWeapon", "entity.EquipWeapon(name, kit?)", "Equipa a arma: procura no kit pedido, no kit do personagem, ou no único kit que a tem. Cria os Motor6D e a hitbox.",
    [["name", "string", "Nome da arma."], ["kit", "string?", "Kit dono (obrigatório se o nome existe em mais de um)."]], "<code>boolean</code>.");
  F(G, "UnequipWeapon", "entity.UnequipWeapon()", "Tira a arma.", null, null);
  F(G, "SetMode", "entity.SetMode(mode)", "Troca o modo (refaz os pontos de attach).", [["mode", "string", "Chave em WeaponData.Modes."]], "<code>boolean</code>.");
  F(G, "GetCurrentMode", "entity.GetCurrentMode()", "Modo atual.", null, "<code>string?</code>.");
  F(G, "GetModeData", "entity.GetModeData()", "Dados do modo atual.", null, "<code>table?</code>.");
  F(G, "GetWeaponData", "entity.GetWeaponData()", "O WeaponData da arma.", null, "<code>table?</code>.");
  F(G, "GetWeapon", "entity.GetWeapon()", "O Model da arma equipada.", null, "<code>Model?</code>.");
  F(G, "GetWeaponName", "entity.GetWeaponName()", "Nome da arma.", null, "<code>string?</code>.");
  F(G, "HasWeapon", "entity.HasWeapon()", "Tem arma?", null, "<code>boolean</code>.");
  F(G, "GetHitOrigin", "entity.GetHitOrigin()", "A peça <code>hitOrigin</code> da arma.", null, "<code>BasePart?</code>.");
  F(G, "GetWeaponPosition", "entity.GetWeaponPosition()", "Posição da arma.", null, "<code>Vector3</code>.");
  F(G, "GetWeaponCFrame", "entity.GetWeaponCFrame()", "CFrame da arma.", null, "<code>CFrame</code>.");
  F(G, "StartHitbox", "entity.StartHitbox(duration, owner?)", "Liga a hitbox da arma para o owner (um runner). Sem owner, a sessão compartilhada. Na skill, use <code>self:StartHitbox</code>.",
    [["duration", "number", "Segundos."], ["owner", "runner?", "Dono (recebe os acertos no onHit)."]], "<code>boolean</code>.", { see: ["api.skill.StartHitbox"] });
  F(G, "StopHitbox", "entity.StopHitbox(owner?)", "Desliga a hitbox do owner (zera a lista de já acertados).", [["owner", "runner?", "Dono."]], null);
  F(G, "IsHitboxActive", "entity.IsHitboxActive(owner?)", "A hitbox está ativa (do owner, ou qualquer)?", [["owner", "runner?", ""]], "<code>boolean</code>.");
  F(G, "AddHitboxOwner", "entity.AddHitboxOwner(owner)", "Interno: o runner passa a receber acertos (o motor faz no start da skill).", null, null);
  F(G, "RemoveHitboxOwner", "entity.RemoveHitboxOwner(owner)", "Interno: o runner sai (no fim da skill).", null, null);
  F(G, "GetActiveHitboxes", "entity.GetActiveHitboxes(owner?)", "Hitboxes ativas (debug).", null, "<code>table</code>.");
  F(G, "GetHitboxConfigs", "entity.GetHitboxConfigs()", "Partes de hitbox achadas na arma (<code>{ name, part, flags }</code>).", null, "<code>table</code>.");
  F(G, "GetHitbox", "entity.GetHitbox()", "O HitboxWrapper da arma.", null, "Wrapper.");
  F(G, "DestroyHitbox", "entity.DestroyHitbox()", "Destrói o wrapper de hitbox.", null, null);

  // ================================================================ Animation
  DOCS.group({
    id: "api.Animation", parent: "api.componentes", title: "Animation",
    kw: "animation animação anim track marker marcador sequência animationlib charlib tocar parar",
    src: "ServerScriptService/EntityData/Components/AnimationComponent",
    lead: "Tracks com chave, marcadores, sequências e a biblioteca de animações do kit. Funciona com Humanoid (Animator) e com rigs customizados (AnimationController).",
    html: `<p>Numa skill, <code>self.charLib</code> é a biblioteca do kit dono: <code>self.charLib.M1.M1Start</code>. Veja ${L("conceitos.personagens")}.</p>`,
  });
  G = "api.Animation";
  F(G, "PlayAnimation", "local track = entity.PlayAnimation(id, key?, fade?, weight?, speed?)", "Toca uma animação. A chave identifica a track (padrão: o próprio id); tocar de novo na mesma chave substitui.",
    [["id", "string | number", "ID da animação."], ["key", "string?", "Chave."], ["fade", "number?", "Fade in (0,1)."], ["weight", "number?", "Peso."], ["speed", "number?", "Velocidade (1)."]],
    "<code>AnimationTrack?</code> (nil sem Animator).", { ex: "local id = self.charLib.M1.M1Start\nlocal track = self.Entity.PlayAnimation(id)\nif track then track.Looped = false end" });
  F(G, "StopAnimation", "entity.StopAnimation(key, fade?)", "Para a track da chave.", [["key", "string", "Chave."], ["fade", "number?", "Fade out."]], null);
  F(G, "StopAllAnimations", "entity.StopAllAnimations(fade?)", "Para todas.", [["fade", "number?", ""]], null);
  F(G, "AdjustSpeed", "entity.AdjustSpeed(key, speed)", "Muda a velocidade de uma track.", [["key", "string", ""], ["speed", "number", ""]], null);
  F(G, "AdjustWeight", "entity.AdjustWeight(key, weight, fade?)", "Muda o peso.", [["key", "string", ""], ["weight", "number", ""], ["fade", "number?", ""]], null);
  F(G, "OnMarker", "local conn = entity.OnMarker(key, marker, callback)", "Conecta um callback a um marcador da track.",
    [["key", "string", "Chave da track (o id, se não passou key)."], ["marker", "string", "Nome do marcador."], ["callback", "function", ""]], "<code>RBXScriptConnection?</code>.",
    { ex: "self.Entity.OnMarker(tostring(id), \"End\", function() self.cleanUp() end)" });
  F(G, "WaitForMarker", "entity.WaitForMarker(key, marker, timeout?)", "Espera o marcador (bloqueia a thread) ou o timeout.", [["key", "string", ""], ["marker", "string", ""], ["timeout", "number?", ""]], "<code>boolean</code> (o marcador chegou).");
  F(G, "GetMarkerSignal", "entity.GetMarkerSignal(key, marker)", "O sinal do marcador.", null, "<code>RBXScriptSignal?</code>.");
  F(G, "PlaySequence", "entity.PlaySequence(steps, index?, loop?)", "Toca uma sequência de animações em ordem, com loop opcional.",
    [["steps", "{ step }", "<code>{ id, key, fade?, weight?, speed?, marker?, delay? }</code>."], ["index", "number?", "Começo (1)."], ["loop", "table?", "<code>{ from, to, count }</code>."]], null);
  F(G, "PlayFromLib", "entity.PlayFromLib(category, name, key?, fade?)", "Toca pela biblioteca do personagem.", [["category", "string", "Conjunto (M1, S1)."], ["name", "string", "Animação."]], "<code>AnimationTrack?</code>.");
  F(G, "GetLibAnimId", "entity.GetLibAnimId(category, name)", "ID na biblioteca.", null, "ID ou <code>nil</code>.");
  F(G, "GetLibCategory", "entity.GetLibCategory(category)", "Um conjunto inteiro.", null, "<code>table?</code>.");
  F(G, "GetTrack", "entity.GetTrack(key)", "A track da chave.", null, "<code>AnimationTrack?</code>.");
  F(G, "IsPlaying", "entity.IsPlaying(key)", "Tocando?", null, "<code>boolean</code>.");
  F(G, "GetAllTracks", "entity.GetAllTracks()", "Todas as tracks ativas.", null, "<code>table</code>.");
  F(G, "GetAnimationType", "entity.GetAnimationType()", "\"Humanoid\" ou \"Custom\".", null, "<code>string</code>.");

  // ================================================================ Control
  DOCS.group({
    id: "api.Control", parent: "api.componentes", title: "Control",
    kw: "control controle possessão possess release lock unlock link pilha stack swap",
    src: "ServerScriptService/EntityData/Components/ControlComponent",
    lead: "Quem dirige a entidade (player ou IA), em pilha. Corta a fonte do input; as permissões continuam nos status.",
    html: `
${T(["Config", "Padrão", "O quê"], [
  ["<code>Policy</code>", "Stack", "<code>ControlComponent.Policy.Stack | Swap</code>."],
  ["<code>PauseAI</code>", "true", "Player assumindo pausa a IA do alvo."],
  ["<code>ReleaseOnDeath</code>", "true", "A morte do possuído devolve o controlador."],
])}
<p>Módulo: <code>ControlComponent.Policy</code>, <code>ControlComponent.GetPossessionOf(player)</code>, <code>ControlComponent.ReleasePlayer(player, leaving?)</code>. Veja ${L("conceitos.controle")}.</p>`,
  });
  G = "api.Control";
  F(G, "Possess", "entity.Possess(controller, opts?)", "Transfere o controle desta entidade.",
    [["controller", "table", "<code>{ Player = p }</code> ou <code>{ AI = true, Brain = fn? }</code>."], ["opts", "table?", "<code>{ Policy?, PauseAI?, ReleaseOnDeath? }</code>."]], "<code>boolean</code>.",
    { ex: "torre.Possess({ Player = player })\n-- ...\ntorre.Release()", see: ["receitas.possessao"] });
  F(G, "Release", "entity.Release()", "Devolve ao controlador nativo (o player volta ao corpo anterior da pilha).", null, "<code>boolean</code> (havia controle não nativo).");
  F(G, "Lock", "entity.Lock()", "Corta o controlador atual sem reatribuir (cutscene, QTE).", null, null);
  F(G, "Unlock", "entity.Unlock()", "Devolve exatamente o que o Lock cortou.", null, null);
  F(G, "GetController", "entity.GetController()", "O controlador atual.", null, "<code>{ Player?, AI?, Brain? }</code>.");
  F(G, "IsControlledBy", "entity.IsControlledBy(player)", "Este player dirige a entidade?", [["player", "Player", ""]], "<code>boolean</code>.");
  F(G, "IsAIControlled", "entity.IsAIControlled()", "Uma IA dirige?", null, "<code>boolean</code>.");
  F(G, "LinkTo", "entity.LinkTo(other, opts)", "O input de movimento/mira desta entidade também vai para <code>other</code> (precisa de Control).",
    [["other", "EntityCore", ""], ["opts", "table", "<code>{ MirrorMovement?, MirrorLook? }</code>."]], null);
  F(G, "Unlink", "entity.Unlink(other)", "Desfaz o link.", null, null);
  F(G, "GetLinkedEntities", "entity.GetLinkedEntities(filter?)", "Entidades linkadas.", [["filter", "string?", "\"MirrorMovement\" | \"MirrorLook\"."]], "<code>{EntityCore}</code>.");

  // ================================================================ AI
  DOCS.group({
    id: "api.AI", parent: "api.componentes", title: "AI",
    kw: "ai ia brain cérebro npc comportamento",
    src: "ServerScriptService/EntityData/Components/AIComponent",
    lead: "Um Brain (function(entity, dt)) chamado a cada Heartbeat, num scheduler único. O Brain gera input pelo SkillHandler, como um player.",
    html: `<p>Config: <code>Brain</code>, <code>Enabled</code> (padrão true). Veja ${L("conceitos.ia")}.</p>`,
  });
  G = "api.AI";
  F(G, "SetBrain", "entity.SetBrain(fn)", "Troca a mente.", [["fn", "function?", "<code>(entity, dt)</code>."]], null);
  F(G, "GetBrain", "entity.GetBrain()", "A mente atual.", null, "<code>function?</code>.");
  F(G, "SetEnabled", "entity.SetEnabled(on)", "Liga/desliga o Brain.", [["on", "boolean", ""]], null);
  F(G, "IsAIEnabled", "entity.IsAIEnabled()", "Ligado?", null, "<code>boolean</code>.");

  // ================================================================ Affiliation
  DOCS.group({
    id: "api.Affiliation", parent: "api.componentes", title: "Affiliation",
    kw: "affiliation afiliação time team facção aliado inimigo",
    src: "ServerScriptService/EntityData/Components/AffiliationComponent",
    lead: "De que lado a entidade está. Só o dado: quem afeta quem é regra do StateTable (Relation, CanAffect, Enum.AffectsDefaults). Sem este componente, a entidade é Neutral.",
    html: `<p>Config: <code>Team</code> (qualquer valor comparável). Veja ${L("conceitos.alvos")}.</p>`,
  });
  G = "api.Affiliation";
  F(G, "GetTeam", "entity.GetTeam()", "O time.", null, "O valor do time.");
  F(G, "SetTeam", "entity.SetTeam(team)", "Troca o time (ex.: controle mental: vira aliado por um tempo).", [["team", "any", ""]], null);
})();

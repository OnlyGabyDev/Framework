/*
  Exemplos de uso: componentes (2/2): Combat, Movement, Weapon, Animation, Control.
  Estilo e requires: ver o topo de 09-exemplos-nucleo.js. Nos exemplos de loadout:
  Keys = require(game.ServerStorage.DataBase.SkillDatabase).Keys e
  Intents = require(game.ReplicatedStorage.Input.Intents).
*/
(function () {
  var X = DOCS.example;

  // ================================================================ Combat: loadout
  X("api.Combat.ApplyLoadout", [
    {
      t: "camada temporária",
      code: `
-- "despertar": por 15 s a Ultimate e o M1 viram outras skills
entity.ApplyLoadout({
    Slots = {
        [Intents.Id.Ultimate] = Keys.Schema.Skill3,
        [Intents.Id.Primary] = golpeDesperto,          -- skill em tabela
    },
}, "Desperto")

task.delay(15, function()
    if entity.Active then entity.RemoveLoadoutLayer("Desperto") end
end)
`,
      desc: `O código acima cria a camada <code>Desperto</code> por cima do loadout atual. Só os slots que ela declara mudam; Dash e as outras habilidades continuam vindo das camadas de baixo. Ao remover a camada, os slots voltam a ser o que eram, sem precisar guardar nada.`,
    },
    {
      t: "lista e slot esvaziado",
      code: `
-- trocar a Base inteira, na ordem dos slots (Primary, Dash, Ability1...)
entity.ApplyLoadout({ List = { Keys.Schema.M1, Keys.Schema.Dash, Keys.Schema.Skill1 } })

-- silêncio parcial: a camada "Selado" esconde a Ultimate da Base
entity.ApplyLoadout({ Slots = { [Intents.Id.Ultimate] = false } }, "Selado")
`,
      desc: `O código acima mostra as duas formas de loadout. Em <code>List</code>, as skills ocupam os slots na ordem de <code>Intents.SkillOrder</code>. Em <code>Slots</code>, <code>false</code> esvazia o slot de propósito: enquanto a camada existir, o botão da Ultimate não faz nada, mesmo com a Base tendo uma Ultimate.`,
    },
  ]);

  X("api.Combat.EquipSkill", [
    {
      t: "skill do banco",
      code: `
local ok = entity.EquipSkill(Intents.Id.Ability2, Keys.Schema.Skill3)
print(ok)   -- true
`,
      desc: `O código acima põe a Skill3 da Schema no slot Ability2 da camada Base. A chave vem do SkillDatabase (<code>Keys.Schema.Skill3</code> vale <code>"Schema_Skill3"</code>); o EquipSkill carimba <code>data.name</code> e <code>data.kit</code> da skill, e é pelo kit que ela acha as próprias animações em qualquer corpo. Slot inválido ou chave inexistente devolvem <code>false</code> com warn.`,
    },
    {
      t: "skill escrita em código",
      code: `
local giro = {
    data = { name = "Giro", cooldown = 4, duration = 0.6, kit = "Schema" },
    callbacks = {
        onStart = function(self)
            self.Entity.PlayAnimation(self.charLib.S1.SpinStart)   -- animação do kit "Schema"
            self:StartHitbox(self.data.duration)
        end,
        onHit = function(self, hit) self:Damage(hit.target, 12, { Hit = hit }) end,
    },
}
entity.EquipSkill(Intents.Id.Ability3, giro)
`,
      desc: `O código acima equipa uma skill que não está no banco: uma tabela <code>{ data, callbacks }</code> criada no próprio script. Ela precisa declarar o que o banco carimbaria sozinho, como o <code>name</code> (usado no cooldown) e, se tocar animações do kit, o <code>kit</code>.`,
    },
  ]);

  X("api.Combat.AddSkill", {
    code: `
-- roguelike: cada baú dá uma skill nova no próximo slot livre
local slot = entity.AddSkill(Keys.Schema.Skill1)
if slot then
    print("skill nova no slot", slot)
else
    print("loadout cheio")
end
`,
    desc: `O código acima equipa uma skill no primeiro slot vazio da camada Base, na ordem de <code>Intents.SkillOrder</code>. O retorno é o slot usado, ou <code>nil</code> com a camada cheia.`,
  });

  X("api.Combat.UnequipSlot", {
    code: `
entity.UnequipSlot(Intents.Id.Ability1, "Desperto")
`,
    desc: `O código acima tira a skill do slot Ability1 da camada <code>Desperto</code>. O slot volta a mostrar o que a camada de baixo tem nele (se tiver). Para esconder o slot de vez enquanto a camada existir, use <code>false</code> no ${L("api.Combat.ApplyLoadout", "ApplyLoadout")}.`,
  });

  X("api.Combat.RemoveLoadoutLayer", {
    code: `
-- o modo da arma acabou
local removida = entity.RemoveLoadoutLayer(Enum.LoadoutLayers.WeaponMode)
`,
    desc: `O código acima tira a camada do modo da arma; os slots que ela trocava voltam a ser os da forma. Devolve <code>false</code> se a camada não existia. A Base não sai (para trocá-la, aplique outro loadout nela).`,
  });

  X("api.Combat.GetLoadoutLayers", {
    code: `
print(table.concat(entity.GetLoadoutLayers(), " < "))
-- Base < WeaponMode < Desperto
`,
    desc: `O código acima mostra as camadas de baixo para cima: a última da lista vence quando duas camadas declaram o mesmo slot. Uma camada vai para o topo quando é criada (a primeira escrita nela).`,
  });

  X("api.Combat.GetSkillFromSlot", {
    code: `
local skill = entity.GetSkillFromSlot(Intents.Id.Ultimate)
if skill then
    print(skill.data.name, skill.data.cooldown)   -- Schema_Ultimate  3
end
`,
    desc: `O código acima lê a skill que o botão da Ultimate dispara agora, já com as camadas aplicadas. É o mesmo que o SkillHandler consulta no cast. A HUD pode usar para mostrar o ícone e o cooldown certos.`,
  });

  X("api.Combat.GetChosenChar", {
    code: `
if entity.GetChosenChar() == "Schema" then
    entity.EquipWeapon("Martelo")
end
`,
    desc: `O código acima lê o kit atual da entidade (a pasta no CharacterDatabase). Com <code>ChosenChar = false</code> no config, a entidade não tem kit e o retorno é <code>nil</code>.`,
  });

  X("api.Combat.GetCharMode", {
    code: `
local proxima = entity.GetCharMode() == "Base" and "Desperta" or "Base"
entity.SetCharMode(entity.GetChosenChar(), proxima)
`,
    desc: `O código acima alterna entre duas formas do mesmo personagem. A forma é o nome do módulo dentro da pasta do kit no CharacterDatabase.`,
  });

  X("api.Combat.SetCharMode", {
    code: `
-- CharacterDatabase/Schema/Desperta.luau existe, com Stats e Loadout próprios
local ok = entity.SetCharMode("Schema", "Desperta")
if ok then
    print(entity.GetStat("Speed"), entity.GetMaxHP())
end
`,
    desc: `O código acima troca o player para a forma <code>Desperta</code>: os Stats da forma viram a base do Attributes (o MaxHP pelo <code>SetMaxHP</code>, mantendo a porcentagem de vida) e o Loadout dela vai para a camada Base. Camadas de cima (modo de arma, buffs de loadout) continuam valendo. Kit ou forma inexistentes dão warn e nada muda.`,
  });

  // ================================================================ Combat: cooldown
  X("api.Combat.HasCooldown", {
    code: `
local function brain(entity, dt)
    if not entity.HasCooldown("Schema_Dash") and alvoMuitoPerto(entity) then
        SkillHandler.HandleIntent(entity.ID,
            Intents.NewEvent(Intents.Id.Dash, Intents.Kind.Activate, Intents.Gesture.Press))
    end
end
`,
    desc: `O código acima faz uma IA só tentar o Dash quando ele está pronto. O nome é o <code>data.name</code> da skill (para skills do banco, a chave: <code>"Schema_Dash"</code>). Com cargas, a skill só está em cooldown quando não sobra nenhuma.`,
  });

  X("api.Combat.GetCooldown", {
    code: `
local restante = entity.GetCooldown("Schema_Ultimate")
print(string.format("Ultimate em %.1f s", restante))
`,
    desc: `O código acima lê quantos segundos faltam para a Ultimate. 0 significa pronta; numa skill com cargas, o retorno é 0 enquanto houver carga.`,
  });

  X("api.Combat.SetCooldown", {
    code: `
-- punição por errar o parry: a skill entra no cooldown cheio do módulo
entity.SetCooldown("Parry")
-- ou um valor qualquer
entity.SetCooldown("Parry", 8)
`,
    desc: `O código acima define o tempo restante do cooldown. Sem segundos, usa o <code>data.cooldown</code> da skill; isso só funciona com skill do banco já equipada (o EquipSkill guarda o módulo pela chave). Para skill em tabela, passe os segundos. Diferente do ${L("api.Combat.StartCooldown")}, não gasta carga.`,
  });

  X("api.Combat.StartCooldown", {
    code: `
-- um item do jogo que usa o mesmo cooldown da skill "Cura"
if not entity.HasCooldown("Cura") then
    entity.Heal(50)
    entity.StartCooldown("Cura", 12)
end
`,
    desc: `O código acima faz um item compartilhar o cooldown de uma skill: usar o item conta 12 s no nome "Cura". É o que o motor faz no cast; com <code>maxCharges</code>, gasta uma carga em vez de travar de vez. Não aplica a redução de cooldown (CooldownReduction) sozinho: para isso, calcule com ${L("api.CooldownPolicy.EffectiveDuration")}.`,
  });

  X("api.Combat.ReduceCooldown", {
    code: `
-- a cada abate, -2 s na Ultimate
entity:Listen({
    Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.OnDeath,
    Owner = StateTable.OwnerToken(entity, "UltNoAbate"),
    Action = function()
        entity.ReduceCooldown("Schema_Ultimate", 2)
    end,
})
`,
    desc: `O código acima encurta a contagem da Ultimate em 2 segundos a cada abate. <span class="badge out">OUT</span> <code>OnDeath</code> chega em quem matou (também numa morte por veneno aplicado por ele). Reduzir uma skill que já está pronta não faz nada.`,
  });

  X("api.Combat.GrantCooldownCharge", {
    code: `
-- investida com 2 cargas (data.cooldownPolicy = { charges = 2 }): acertar devolve a carga
onHit = function(self, hit)
    self:Damage(hit.target, 5, { Hit = hit })
    self.Entity.GrantCooldownCharge(self.data.name)
end,
`,
    desc: `O código acima devolve a carga gasta quando a investida acerta, permitindo emendar outra. Numa skill sem cargas, o efeito é deixá-la pronta na hora.`,
  });

  X("api.Combat.GetCooldownCharges", {
    code: `
local atuais, maximo = entity.GetCooldownCharges("Schema_Dash")
if atuais then
    print(atuais .. "/" .. maximo)   -- 1/2
end
`,
    desc: `O código acima mostra quantas cargas do Dash sobram. Uma skill que não usa cargas devolve <code>nil, nil</code>.`,
  });

  X("api.Combat.ExportCooldown", {
    code: `
local estado = player.ExportCooldown("Schema_Ultimate")
-- { remaining = 6.2, duration = 10, charges = nil, maxCharges = nil }, ou nil se pronta
clone.ImportCooldown("Schema_Ultimate", estado)
`,
    desc: `O código acima copia o cooldown da Ultimate do player para um clone dele. O estado é relativo (segundos restantes, não horário), então pode ser aplicado em outra entidade ou guardado e reaplicado depois. Para o caso comum, ${L("api.CooldownPolicy.Transfer")} faz as duas chamadas.`,
  });

  X("api.Combat.ImportCooldown", {
    code: `
-- trocar de personagem sem "resetar" a Ultimate
local salvo = entity.ExportCooldown("Schema_Ultimate")
entity.SetCharMode("Schema", "Desperta")
entity.ImportCooldown("Schema_Ultimate", salvo)
`,
    desc: `O código acima preserva o cooldown de uma skill numa troca de forma. Importar <code>nil</code> deixa a skill pronta.`,
  });

  X("api.Combat.ResetCooldown", {
    code: `
-- pegou o orbe: a Ultimate fica pronta
entity.ResetCooldown("Schema_Ultimate")
`,
    desc: `O código acima deixa a Ultimate pronta na hora. Numa skill com cargas, devolve todas.`,
  });

  X("api.Combat.ResetAllCooldowns", {
    code: `
-- começo de rodada
for _, player in game.Players:GetPlayers() do
    local e = DataManager.Get(player)
    if e then e.ResetAllCooldowns() end
end
`,
    desc: `O código acima deixa todas as skills de todos os players prontas no começo de uma rodada.`,
  });

  // ================================================================ Combat: skills ativas
  X("api.Combat.GetActiveSkills", {
    code: `
for nome, runners in entity.GetActiveSkills() do
    for _, runner in runners do
        print(nome, runner.state, runner.elapsedTime)
    end
end
`,
    desc: `O código acima lista as skills rodando na entidade e o estado de cada ativação (Casting, Running). Com o nome da skill, devolve só os runners dela (uma lista vazia se não houver nenhum).`,
  });

  X("api.Combat.GetActiveSkillCount", {
    code: `
-- torre: no máximo 3 projéteis vivos
if entity.GetActiveSkillCount("Projetil") >= 3 then return end
`,
    desc: `O código acima limita quantas ativações de uma skill podem estar vivas. O motor já faz isso pelo <code>data.maxInstances</code> no cast; a contagem serve para regras do jogo fora do cast.`,
  });

  X("api.Combat.HasActiveSkill", {
    code: `
-- durante a Ultimate, o dano recebido cai pela metade
entity:Listen({
    Role = Enum.Roles.IN, Breakpoint = Enum.Breakpoints.PreDamage,
    Action = function(ctx)
        if entity.HasActiveSkill("Schema_Ultimate") then ctx.damage *= 0.5 end
    end,
})
`,
    desc: `O código acima reduz o dano recebido enquanto a Ultimate está rodando. Para algo que só vale durante a skill, também dá para inscrever com <code>self:Listen</code> no <code>onStart</code> dela: a reação sai sozinha no fim.`,
  });

  X("api.Combat.StopAllActiveSkills", {
    code: `
-- tempo esgotado: todas as skills dos players param (cancelamento)
for _, player in game.Players:GetPlayers() do
    local e = DataManager.Get(player)
    if e then e.StopAllActiveSkills(true, Enum.Types.Skill) end
end
`,
    desc: `O código acima cancela as skills ativas de cada player. Com <code>true</code>, é cancelamento: roda o <code>onCancel</code> de cada uma, e a skill que devolver <code>false</code> nele continua viva. O 2º argumento restringe ao tipo de runner.`,
  });

  X("api.Combat.InterruptSkills", {
    code: `
-- "grito": interrompe o que o alvo está fazendo, sem atordoar
onHit = function(self, hit)
    if hit.target:HasComponent(Component.Combat) then
        hit.target.InterruptSkills()
    end
end,
`,
    desc: `O código acima interrompe as skills do alvo, com o motivo <code>interrupted</code>. Skills com a trait <code>Uninterruptible</code> passam ilesas. O mesmo acontece sozinho quando entra um estado com a tag <code>interrupt</code>, como o Stun; chame à mão para interromper sem aplicar estado.`,
  });

  X("api.Combat.CanContinue", {
    code: `
onStep = function(self, dt)
    -- canal: se a entidade foi silenciada no meio, para
    if not self.Entity.CanContinue(self) then
        return self:Stop(true)
    end
end,
`,
    desc: `O código acima encerra uma skill canalizada quando a entidade perde a permissão de castar (morreu, ou a tag <code>canCast</code> ficou falsa por um Silence). É a mesma checagem que o SkillHandler faz antes de um cast.`,
  });

  X("api.Combat.TrySelfCancel", {
    code: `
-- um script de "esquiva de emergência" fora do sistema de input
if entity.TrySelfCancel() then
    entity.AddForce({ Type = "Esquiva", Duration = 0.2, Speed = 70, Hard = true,
        Direction = -entity.GetLookDirection() })
end
`,
    desc: `O código acima tenta largar a ação atual antes de esquivar. Só uma ação com ActionState <b>Self</b> se deixa cancelar assim; <b>Out</b> e <b>LockedCast</b> devolvem <code>false</code> (é o que impede um golpe de ser interrompido pelo próprio dono). Sem ActionState, devolve <code>true</code>.`,
  });

  X("api.Combat.SetActionState", {
    code: `
onStart = function(self)
    -- golpe pesado: nem o Dash o cancela
    self.Entity.SetActionState(self.statusTable.ActionStates.LockedCast, self.Runner)
end,
`,
    desc: `O código acima trava a ação da entidade durante a skill. Com <code>ActionStates.Self.selfCast</code>, a próxima skill cancela esta (combo fluido); com <code>Out.cast</code> ou <code>LockedCast</code>, a próxima é recusada até esta acabar. O ActionState sai sozinho no fim do runner dono.`,
  });

  X("api.Combat.GetActionState", {
    code: `
local estado = entity.GetActionState()
if estado then
    print(estado.name, estado.runner.skillName)   -- Cast  Schema_M1
end
`,
    desc: `O código acima mostra a trava de ação atual e a skill dona dela. Os nomes são <code>SelfCast</code>, <code>SelfGlobalCast</code>, <code>Cast</code>, <code>OutGlobalCast</code> e <code>LockedCast</code>.`,
  });

  X("api.Combat.RemoveActionState", {
    code: `
onHit = function(self, hit)
    self:Damage(hit.target, 20, { Hit = hit })
    -- acertou: libera o personagem para emendar outra skill antes da animação acabar
    self.Entity.RemoveActionState(self.Runner)
end,
`,
    desc: `O código acima solta a trava de ação no momento do acerto (o "cancel window" de jogos de luta). Passando o runner, a trava só sai se ainda for desta skill: uma limpeza atrasada não apaga a trava de uma skill nova.`,
  });

  X("api.Combat.ApplyDamage", {
    code: `
-- dano disparado fora de uma skill, mas com crédito para o runner de uma armadilha
local ok, dano = dono.ApplyDamage(30, runnerDaArmadilha, vitima, {
    Traits = { "Fogo" },
    Effects = { StateTable.Status.Bleed },
})
`,
    desc: `O código acima causa dano do lado do atacante: aplica o <code>DamageMult</code> de <code>dono</code>, emite o <span class="badge out">OUT</span> <code>onHit</code> dele (onde listeners podem mudar o dano) e então chama o <code>TakeDamage</code> da vítima. As opções somam traits e efeitos só a este golpe. Dentro de uma skill, <code>self:Damage</code> faz exatamente isto com o runner já preenchido.`,
  });

  X("api.Combat.AddActiveSkill", {
    code: `
-- o que o SkillRunner faz no start de uma skill:
if entity:HasComponent(Component.Combat) then
    entity.AddActiveSkill(runner.skillName, runner)
end
`,
    desc: `O código acima mostra o registro interno de uma skill como ativa, feito pelo motor no início de todo runner de skill. É por esse registro que funcionam <code>maxInstances</code>, o recast, a interrupção e o cancelamento na morte. O jogo não precisa chamar.`,
  });

  X("api.Combat.RemoveActiveSkill", {
    code: `
-- o que o SkillRunner faz no fim:
entity.RemoveActiveSkill(runner.skillName, runner)
print(entity.GetActiveSkillCount(runner.skillName))
`,
    desc: `O código acima mostra a saída de um runner da lista de ativas, feita pelo motor no fim de toda skill. Chamar à mão deixaria um runner vivo fora da lista (sem recast, sem interrupção): não chame.`,
  });

  X("api.Combat.SetIntentRunner", {
    code: `
-- o que o SkillHandler faz quando uma intent de Hold ativa uma skill:
entity.SetIntentRunner(event.Intent, runner)
-- ...e no Release do mesmo botão:
local alvo = entity.TakeIntentRunner(event.Intent)
if alvo then alvo:Release(event) end
`,
    desc: `O código acima mostra como o Release de um botão chega na ativação certa: o runner que a intent ligou fica guardado pela intent até o botão subir, mesmo que o slot mude no meio. Uso interno do SkillHandler.`,
  });

  X("api.Combat.TakeIntentRunner", {
    code: `
local runner = entity.TakeIntentRunner(Intents.Id.Primary)
print(runner and runner.skillName)          -- Schema_M1
print(entity.TakeIntentRunner(Intents.Id.Primary))   -- nil: o primeiro Take já limpou
`,
    desc: `O código acima pega o runner guardado para a intent e o tira de lá. Uso interno do SkillHandler no Release; veja ${L("api.Combat.SetIntentRunner")}.`,
  });

  // ================================================================ Movement
  X("api.Movement.AddForce", [
    {
      t: "knockback",
      code: `
onHit = function(self, hit)
    self:Damage(hit.target, 10, { Hit = hit })
    local dir = hit.target.GetPosition() - self.Entity.GetPosition()
    hit.target.AddForce({
        Type = "Knockback", Duration = 0.25, Speed = 60,
        Direction = Vector3.new(dir.X, 0, dir.Z).Unit,
        Hard = true, RequiresControl = false, Priority = 5,
    })
end,
`,
      desc: `O código acima empurra o alvo para longe de quem bateu, no plano, por 0,25 s. <code>RequiresControl = false</code> marca a Force como externa: ela vale mesmo com o alvo em Stun (sem <code>canMove</code>), mas é barrada se o alvo estiver com <code>canDisplace = false</code>. <code>Hard</code> fixa os eixos: o alvo não consegue andar contra o empurrão.`,
    },
    {
      t: "dash com direção do input",
      code: `
onStart = function(self)
    local dir = self.Entity.GetDirection()
    if dir.Magnitude < 0.1 then dir = self.Entity.GetLookDirection() end
    self.forceID = self.Entity.AddForce({
        Type = "Dash", Duration = 0.3, Speed = 80, Direction = dir,
        Hard = true, IgnoreGravity = true, Priority = 10,
    })
end,
onEnd = function(self)
    if self.forceID then self.Entity.RemoveForce(self.forceID) end
end,
`,
      desc: `O código acima é um dash para onde o player está andando (ou para onde olha, se estiver parado), sem cair durante ele. A Force é própria (<code>RequiresControl</code> padrão <code>true</code>): um Stun no meio a cancela. O ID é guardado para tirar a Force se a skill acabar antes.`,
    },
    {
      t: "corrente de vento que renova",
      code: `
-- chamado a cada poll de uma zona: a mesma Key renova a Force em vez de empilhar
e.AddForce({
    Key = "Corrente_" .. zona.ID, Type = "Vento",
    Duration = 0.5, Speed = 25, Direction = Vector3.new(1, 0, 0),
    RequiresControl = false,   -- Soft (Hard = false): soma com a caminhada
})
`,
      desc: `O código acima aplica um vento que soma com a caminhada (Soft) e é renovado a cada chamada pela <code>Key</code>, em vez de criar uma Force nova. Para zonas, ${L("api.AreaBehaviors.BindDirectionalForce")} já faz isso e ainda tira a Force na saída.`,
    },
  ]);

  X("api.Movement.RemoveForce", {
    code: `
local id = entity.AddForce({ Type = "Voo", Duration = 20, Speed = 40, Hard = true,
    IgnoreGravity = true, Direction = function(_, _, ctx) return ctx.Entity.GetAimDirection() end })

-- apertou o botão de novo: pousa
entity.RemoveForce(id)
`,
    desc: `O código acima encerra um voo antes da duração. Remover pelo ID chama o <code>OnEnd</code> da Force, se ela tiver.`,
  });

  X("api.Movement.RemoveForceByKey", {
    code: `
zona:OnExit(function(e)
    e.RemoveForceByKey("Corrente_" .. zona.ID)
end)
`,
    desc: `O código acima tira a Force de vento de quem sai da zona. Quem aplica uma Force por <code>Key</code> e não guarda o ID (porque ela é renovada a cada poll) a encerra pela mesma Key. Devolve <code>false</code> se não havia Force com ela.`,
  });

  X("api.Movement.ClearForces", {
    code: `
-- respawn no checkpoint: nada de dash ou knockback pela metade
entity.ClearForces()
entity.Teleport(checkpoint.Position)
`,
    desc: `O código acima remove todas as Forces ativas antes de teleportar, para o corpo não chegar ao destino ainda sendo empurrado. Cada Force removida roda o próprio <code>OnEnd</code>.`,
  });

  X("api.Movement.AttachTo", [
    {
      t: "agarrão de skill",
      code: `
onHit = function(self, hit)
    local release = hit.target.AttachTo(self.Entity.GetRoot(), CFrame.new(0, 0, -4))
    if not release then return end
    local restaura = CollisionGroups.Assign(hit.target.Instance, CollisionGroups.Grabbed)
    self:Own(function()
        release()
        restaura()
    end)
end,
`,
      desc: `O código acima agarra o alvo e o carrega 4 studs à frente de quem casta, até a skill acabar. O agarrão é um WeldConstraint: não tem atraso nem quando quem agarra é um player. Enquanto preso, o alvo não anda nem sofre Forces. O <code>Own</code> solta no fim do runner por qualquer motivo (fim, cancelamento, morte de quem agarrou).`,
    },
    {
      t: "montaria",
      code: `
local function montar(player, cavalo)
    local cavaleiro = DataManager.Get(player)
    local sela = cavalo.Instance.Sela
    local release = cavaleiro.AttachTo(sela, CFrame.new(0, 2.5, 0), { Massless = true })
    return release   -- chame para desmontar
end
`,
      desc: `O código acima prende o player na sela de um cavalo. <code>Massless = true</code> (o padrão) faz o corpo preso não pesar no cavalo. Se o cavalo for destruído, o weld quebra e o player é solto sozinho.`,
    },
  ]);

  X("api.Movement.Detach", {
    code: `
-- o alvo agarrado levou um Stun de outra fonte: solta
alvo:Listen({
    Role = Enum.Roles.IN, Breakpoint = Enum.Breakpoints.OnInterrupt,
    Action = function() alvo.Detach() end,
})
`,
    desc: `O código acima solta o agarrão atual da entidade sem precisar da função <code>release</code> que o AttachTo devolveu. Devolve <code>false</code> se ela não estava presa.`,
  });

  X("api.Movement.GetAttachment", {
    code: `
local preso = alvo.GetAttachment()
if preso then
    print("preso em", preso.Leader:GetFullName())
end
`,
    desc: `O código acima confere se a entidade está presa e em que peça. O retorno é uma cópia (<code>{ Leader, Offset }</code>); mexer nela não muda o agarrão.`,
  });

  X("api.Movement.SetDirection", {
    code: `
-- um NPC sem Brain sendo empurrado por um script de cutscene
npc.SetDirection(Vector3.new(0, 0, -1))
task.wait(2)
npc.SetDirection(Vector3.zero)
`,
    desc: `O código acima faz um NPC andar para a frente por 2 segundos. A direção é a intenção de movimento (o "WASD" da entidade); o MovementController anda com ela usando a velocidade do stat Speed. Para NPCs com IA, prefira <code>SkillHandler.HandleMovementInput</code>, que também repassa a direção às entidades linkadas.`,
  });

  X("api.Movement.GetDirection", {
    code: `
onStart = function(self)
    local dir = self.Entity.GetDirection()
    if dir.Magnitude < 0.1 then
        -- parado: golpe no lugar
    else
        -- andando: golpe com avanço
    end
end,
`,
    desc: `O código acima escolhe a variação do golpe pelo input de movimento no momento do cast. <code>GetDirection</code> é o input ao vivo: <code>Vector3.zero</code> quando o player soltou todas as teclas.`,
  });

  X("api.Movement.GetLastDirection", {
    code: `
local dir = entity.GetDirection()
if dir.Magnitude < 0.1 then dir = entity.GetLastDirection() end
`,
    desc: `O código acima usa a última direção em que a entidade andou quando ela está parada, para um dash não sair "para lugar nenhum". A última direção nunca é zero depois da primeira vez que a entidade se moveu.`,
  });

  X("api.Movement.GetIntentDirection", {
    code: `
onStart = function(self)
    local lado = self.Entity.GetIntentDirection()
    if lado == "Back" or lado == "BackLeft" or lado == "BackRight" then
        self.Entity.PlayFromLib("M1", "Recuo")    -- uma animação "Recuo" do seu kit
    else
        self.Entity.PlayFromLib("M1", "M1Start")
    end
end,
`,
    desc: `O código acima escolhe a animação do golpe conforme o player anda para trás ou não, em relação à câmera. O retorno é o octante do input relativo a quem olha: <code>Forward</code>, <code>ForwardRight</code>, <code>Right</code>, <code>BackRight</code>, <code>Back</code>, <code>BackLeft</code>, <code>Left</code>, <code>ForwardLeft</code> ou <code>None</code> (parado).`,
  });

  X("api.Movement.SetAimDirection", {
    code: `
-- uma torre controlada por script mira no player mais próximo
local alvo = maisProximo(torre, players, 100)
if alvo then
    torre.SetAimDirection((alvo.GetPosition() - torre.GetPosition()).Unit)
end
`,
    desc: `O código acima aponta a mira 3D de uma entidade. A direção plana (<code>GetLookDirection</code>) é atualizada junto; mirar reto para cima ou para baixo mantém a última direção plana válida. Para players, quem chama isto é o servidor a partir da câmera do cliente.`,
  });

  X("api.Movement.GetAimDirection", {
    code: `
onStart = function(self)
    -- disparo para onde a câmera aponta, inclusive para cima
    local origem = self.Entity.GetCFrame().Position + Vector3.new(0, 1.5, 0)
    local mira = self.Entity.GetAimDirection()
    lancarProjetil(origem, mira)
end,
`,
    desc: `O código acima dispara na direção exata da câmera, com inclinação (pitch). Use a mira 3D para tiro e voo; para golpes no chão, use ${L("api.Movement.GetLookDirection")}, que é plana.`,
  });

  X("api.Movement.GetLookDirection", {
    code: `
local look = self.Entity.GetLookDirection()
local frente = self.Entity.GetPosition() + look * 6
`,
    desc: `O código acima calcula um ponto 6 studs à frente de onde a entidade olha, no plano (sem altura). É a direção de combate: golpes, cones e dashes parados usam esta.`,
  });

  X("api.Movement.GetAirState", {
    code: `
onStart = function(self)
    if self.Entity.GetAirState() ~= "Grounded" then
        return self:Fizzle()   -- esta skill só sai do chão
    end
end,
`,
    desc: `O código acima recusa a skill se a entidade não estiver no chão (o cooldown volta pelo Fizzle). Os valores são <code>Grounded</code>, <code>Jumping</code>, <code>Falling</code> e <code>Floating</code>; Floating é quando algo segura o eixo Y de propósito (um voo, uma Force Hard sem gravidade, GravityScale 0).`,
  });

  X("api.Movement.SetSpeed", {
    code: `
-- efeito visual instantâneo de "tropeço" (1 frame)
entity.SetSpeed(0)
-- no frame seguinte o MovementController relê o stat Speed e volta ao normal

-- para lentidão de verdade, use o stat:
entity.AddModifier(Enum.Stats.Speed, "Lama", Enum.ModifierType.MultPercent, 0.5)
`,
    desc: `O código acima mostra por que <code>SetSpeed</code> raramente é o que você quer: ele escreve direto no corpo, e o MovementController relê o stat <code>Speed</code> a cada frame, desfazendo a mudança. Mudança que dura vai no stat (modificador ou <code>SetStat</code>).`,
  });

  X("api.Movement.SetJumpForce", {
    code: `
-- pulo duplo da forma "Leve": o valor duradouro vai no stat
entity.SetStat(Enum.Stats.JumpForce, 80)
`,
    desc: `O código acima aumenta o pulo de forma duradoura pelo stat <code>JumpForce</code>. <code>SetJumpForce</code> escreve direto no corpo e, como o <code>SetSpeed</code>, é desfeito no frame seguinte pelo MovementController, que relê o stat.`,
  });

  X("api.Movement.SetFrozen", {
    code: `
-- tela de carregamento: o corpo fica parado, sem ser um estado de combate
entity.SetFrozen(true)
carregarMapa()
entity.SetFrozen(false)
`,
    desc: `O código acima congela o corpo durante um carregamento. Use só para parada "de sistema" (cutscene, loading). Para controle de grupo, use estados (Root, Stun): eles combinam com as Forces, aparecem nas tags e respeitam imunidades.`,
  });

  X("api.Movement.AddFilter", {
    code: `
-- chefe imune a knockback e a vento, mas não ao próprio dash
chefe.AddFilter("Inabalavel", function(force)
    return force.RequiresControl ~= false
end)
`,
    desc: `O código acima recusa toda Force externa no chefe (as que têm <code>RequiresControl = false</code>, como knockback e vento), mantendo as próprias. O filtro recebe a tabela da Force antes de ela entrar; devolver <code>false</code> faz o <code>AddForce</code> devolver <code>nil</code>.`,
  });

  X("api.Movement.RemoveFilter", {
    code: `
-- a armadura do chefe quebrou: volta a ser empurrável
chefe.RemoveFilter("Inabalavel")
`,
    desc: `O código acima tira o filtro pelo mesmo ID usado no ${L("api.Movement.AddFilter", "AddFilter")}.`,
  });

  X("api.Movement.GetForceSpeedBudget", {
    code: `
local h, v = player.GetForceSpeedBudget()
print(string.format("Forces somam %.1f studs/s no plano e %.1f na vertical", h, v))
`,
    desc: `O código acima mostra quanto as Forces estão deslocando a entidade além da caminhada. É o crédito que a validação de movimento soma ao WalkSpeed (um dash legítimo não vira correção); útil para depurar um "puxão de volta".`,
  });

  X("api.Movement.SetDrivesInput", {
    code: `
-- o que o Control faz quando um player possui um NPC:
npc.SetDrivesInput(false)   -- o cliente do player passa a simular o corpo
-- ...e no Release:
npc.SetDrivesInput(true)    -- o servidor volta a dirigir
`,
    desc: `O código acima mostra a troca de quem dirige o corpo, feita pela possessão. Uso interno: o jogo usa ${L("api.Control.Possess", "Possess")} e ${L("api.Control.Release", "Release")}.`,
  });

  X("api.Movement.SetMovement", {
    code: `
-- o que o DataManager faz no fim do Create, se a entidade tem Movement:
if core:HasComponent(Component.Movement) then
    core.SetMovement()
end
`,
    desc: `O código acima liga o corpo ao MovementController (cria o wrapper de movimento e registra a entidade). Chamado uma vez pelo DataManager; uma segunda chamada devolve <code>false</code> e não faz nada.`,
  });

  X("api.Movement.GetMovementWrapper", {
    code: `
local wrapper = npc.GetMovementWrapper()
print(wrapper and wrapper:GetAirState())
`,
    desc: `O código acima lê o wrapper de movimento (a camada que aplica caminhada e Forces num corpo com ou sem Humanoid). Serve para depuração; o jogo usa as funções da entidade.`,
  });

  // ================================================================ Weapon
  X("api.Weapon.EquipWeapon", {
    code: `
-- o chefe pega a arma da Schema
if not chefe.EquipWeapon("Martelo", "Schema") then
    warn("arma não encontrada")
end
`,
    desc: `O código acima equipa uma arma de <code>Assets/Weapons</code>: cria o Model, os Motor6D nos pontos de attach do modo padrão e a hitbox. O kit é opcional quando o nome só existe num kit (ou no kit do próprio personagem); passe-o quando o mesmo nome existir em mais de um.`,
  });

  X("api.Weapon.UnequipWeapon", {
    code: `
-- desarmar: a arma some até o fim do efeito
local nome = alvo.GetWeaponName()
alvo.UnequipWeapon()
task.delay(4, function()
    if alvo.Active and nome then alvo.EquipWeapon(nome) end
end)
`,
    desc: `O código acima tira a arma do alvo por 4 segundos e a devolve depois. Sem arma, skills que declaram <code>requires = { Component.Weapon }</code> continuam podendo castar (o componente existe), mas <code>self:StartHitbox</code> não liga nada.`,
  });

  X("api.Weapon.SetMode", {
    code: `
-- trocar o modo direto, sem a skill de transformação
if entity.SetMode("Merged") then
    entity.ApplyLoadout(entity.GetModeData().Loadout, Enum.LoadoutLayers.WeaponMode)
end
`,
    desc: `O código acima troca a arma para o modo <code>Merged</code> e aplica o loadout do modo na camada WeaponMode. <code>SetMode</code> refaz os pontos de attach; o loadout do modo é do jogo aplicar (a skill WeaponTransform da Schema faz isso no fim da animação).`,
  });

  X("api.Weapon.GetCurrentMode", {
    code: `
local proximo = entity.GetCurrentMode() == "Dual" and "Merged" or "Dual"
`,
    desc: `O código acima escolhe o modo seguinte a partir do atual. O modo inicial é o <code>DefaultMode</code> do WeaponData.`,
  });

  X("api.Weapon.GetModeData", {
    code: `
local modo = entity.GetModeData()
print(modo.TransformTime, modo.AnimSet)   -- 0.5  DualBlades
`,
    desc: `O código acima lê os dados do modo atual no WeaponData: pontos de attach, loadout, conjunto de animação, tempo de transformação e o que mais o jogo declarar lá.`,
  });

  X("api.Weapon.GetWeaponData", {
    code: `
local data = entity.GetWeaponData()
for nome in data.Modes do print("modo:", nome) end
`,
    desc: `O código acima lista os modos que a arma declara. O WeaponData é o módulo ao lado do Model da arma em <code>Assets/Weapons/&lt;Kit&gt;/&lt;Arma&gt;</code>.`,
  });

  X("api.Weapon.GetWeapon", {
    code: `
local arma = entity.GetWeapon()
if arma then
    for _, p in arma:GetDescendants() do
        if p:IsA("BasePart") then p.Color = Color3.fromRGB(255, 120, 0) end
    end
end
`,
    desc: `O código acima pinta de laranja o Model da arma equipada (um "encantamento de fogo"). É o clone que está no personagem, não o asset original.`,
  });

  X("api.Weapon.GetWeaponName", {
    code: `
print(entity.GetWeaponName())   -- Martelo
`,
    desc: `O código acima lê o nome da arma equipada, o mesmo usado no ${L("api.Weapon.EquipWeapon", "EquipWeapon")}. Sem arma, <code>nil</code>.`,
  });

  X("api.Weapon.HasWeapon", {
    code: `
onStart = function(self)
    if not self.Entity.HasWeapon() then
        return self:Fizzle()   -- desarmado: não gasta o cooldown
    end
    self:StartHitbox(self.data.duration)
end,
`,
    desc: `O código acima desiste do golpe se a entidade estiver desarmada no momento do cast, devolvendo o cooldown.`,
  });

  X("api.Weapon.GetHitOrigin", {
    code: `
onStart = function(self)
    local ponta = self.Entity.GetHitOrigin()
    if ponta then
        VFXManager.PlayNear(ponta.Position, 150, "Faisca", { Position = ponta.Position })
    end
end,
`,
    desc: `O código acima toca um efeito na ponta da arma. A peça <code>hitOrigin</code> do Model da arma marca de onde saem efeitos e projéteis; na skill ela também está em <code>self.hitPoint</code>.`,
  });

  X("api.Weapon.GetWeaponPosition", {
    code: `
SoundManager.PlayOneShot3D(entity.GetWeaponPosition(), "rbxassetid://1234567")
`,
    desc: `O código acima toca um som na posição da arma (o pivot do Model). Sem arma, devolve <code>Vector3.zero</code>.`,
  });

  X("api.Weapon.GetWeaponCFrame", {
    code: `
local cf = entity.GetWeaponCFrame()
local hitbox, carrier = HitboxSpawner.Spawn(entity, cf * CFrame.new(0, 0, -2))
`,
    desc: `O código acima cria uma hitbox solta 2 studs à frente da arma, na orientação dela. Sem arma, devolve <code>CFrame.identity</code>.`,
  });

  X("api.Weapon.StartHitbox", {
    code: `
-- um script de evento (não uma skill) liga a hitbox da arma por 0,5 s
entity.StartHitbox(0.5)
`,
    desc: `O código acima liga a hitbox da arma numa sessão sem dona (compartilhada): os acertos vão para o <code>onHit</code> de todas as skills ativas que usam a arma. Dentro de uma skill, use <code>self:StartHitbox</code>, que abre a sessão da própria skill e entrega os acertos só no <code>onHit</code> dela. Devolve <code>false</code> se a sessão já estava ligada.`,
  });

  X("api.Weapon.StopHitbox", {
    code: `
entity.StartHitbox(2)
task.wait(0.3)
entity.StopHitbox()          -- desliga a sessão compartilhada

-- a de uma skill: passe o runner (é o que o self:StopHitbox faz)
entity.StopHitbox(runner)
`,
    desc: `O código acima desliga a hitbox antes da duração. Sem argumento, desliga a sessão compartilhada; com o runner, a sessão daquela skill. Desligar também zera a lista de quem já foi acertado: um <code>StartHitbox</code> em seguida pode acertar os mesmos alvos de novo. Para apagar a hitbox da arma de vez, é ${L("api.Weapon.DestroyHitbox")}.`,
  });

  X("api.Weapon.IsHitboxActive", {
    code: `
print(entity.IsHitboxActive())         -- alguma sessão ligada?
print(entity.IsHitboxActive(runner))   -- a sessão desta skill está ligada?
`,
    desc: `O código acima pergunta se a hitbox está ligada. O estado vem das hitboxes de fato ativas, então uma sessão que acabou pela duração já conta como desligada.`,
  });

  X("api.Weapon.AddHitboxOwner", {
    code: `
-- o que o SkillRunner faz no start de uma skill, se a entidade tem Weapon:
entity.AddHitboxOwner(runner)
`,
    desc: `O código acima registra um runner como dono de hitbox: a partir daí ele pode abrir a própria sessão e recebe os acertos da sessão compartilhada. Uso interno do motor.`,
  });

  X("api.Weapon.RemoveHitboxOwner", {
    code: `
-- o que o SkillRunner faz no fim:
entity.RemoveHitboxOwner(runner)   -- a sessão dele desliga junto
`,
    desc: `O código acima tira o runner dos donos de hitbox e desliga a sessão dele. É por isso que a hitbox de uma skill nunca sobrevive ao fim dela. Uso interno do motor.`,
  });

  X("api.Weapon.GetActiveHitboxes", {
    code: `
for nome in entity.GetActiveHitboxes() do
    print("hitbox ativa:", nome)
end
`,
    desc: `O código acima lista, para depuração, as hitboxes ligadas agora (o nome é o da peça de hitbox da arma). Com um runner, só as da sessão dele.`,
  });

  X("api.Weapon.GetHitboxConfigs", {
    code: `
for nome, cfg in entity.GetHitboxConfigs() do
    print(nome, cfg.part:GetFullName())
end
`,
    desc: `O código acima lista as peças de hitbox que o componente encontrou no Model da arma. Se a lista vier vazia, a arma não tem peças de hitbox e <code>StartHitbox</code> avisa "Nenhuma hitbox configurada".`,
  });

  X("api.Weapon.GetHitbox", {
    code: `
local wrapper = entity.GetHitbox()
print(wrapper and wrapper:IsHitboxActive())
`,
    desc: `O código acima lê o HitboxWrapper da arma, o objeto que guarda as sessões por skill. O jogo usa as funções da entidade; o wrapper é para depuração.`,
  });

  X("api.Weapon.DestroyHitbox", {
    code: `
-- a arma vira só enfeite durante a cutscene
entity.DestroyHitbox()
-- para ter hitbox de novo, equipe a arma outra vez
entity.EquipWeapon(entity.GetWeaponName())
`,
    desc: `O código acima apaga a hitbox da arma inteira: desliga todas as sessões e destrói o wrapper (não o Model da arma). Diferente de ${L("api.Weapon.StopHitbox")}, que só desliga: depois do Destroy, só um novo <code>EquipWeapon</code> recria a hitbox.`,
  });

  // ================================================================ Animation
  X("api.Animation.PlayAnimation", [
    {
      t: "animação da skill",
      code: `
onStart = function(self)
    local id = self.charLib.M1.M1Start
    self.track = self.Entity.PlayAnimation(id)
    if self.track then self.track.Looped = false end
end,
onEnd = function(self)
    self.Entity.StopAnimation(tostring(self.charLib.M1.M1Start), 0.2)
end,
`,
      desc: `O código acima toca a animação do golpe pela biblioteca do kit da skill e a para no fim. Sem chave, a track é guardada pelo próprio ID (<code>tostring(id)</code>), e é essa chave que <code>StopAnimation</code> e <code>OnMarker</code> usam. Rig sem Animator devolve <code>nil</code>, por isso o <code>if</code>.`,
    },
    {
      t: "chave própria, fade, peso e velocidade",
      code: `
-- postura de bloqueio por cima da corrida, em câmera lenta
entity.PlayAnimation("rbxassetid://123456789", "Postura", 0.25, 0.8, 0.5)
`,
      desc: `O código acima toca uma animação com chave <code>Postura</code>, fade de entrada de 0,25 s, peso 0,8 e meia velocidade. Tocar outra animação na mesma chave para a anterior primeiro: uma chave é uma "camada" que só toca uma coisa por vez.`,
    },
  ]);

  X("api.Animation.StopAnimation", {
    code: `
entity.StopAnimation("Postura", 0.3)
`,
    desc: `O código acima para a track da chave <code>Postura</code> com fade de saída de 0,3 s (padrão 0,1). Chave sem track tocando é ignorada.`,
  });

  X("api.Animation.StopAllAnimations", {
    code: `
alvo:Listen({
    Role = Enum.Roles.IN, Breakpoint = Enum.Breakpoints.OnDeath,
    Action = function() alvo.StopAllAnimations(0) end,
})
`,
    desc: `O código acima corta todas as animações na hora da morte, para o ragdoll ou a animação de morte do jogo começar limpa.`,
  });

  X("api.Animation.AdjustSpeed", {
    code: `
-- hitstop: congela a animação do golpe por 0,08 s no acerto
onHit = function(self, hit)
    local chave = tostring(self.charLib.M1.M1Start)
    self.Entity.AdjustSpeed(chave, 0)
    task.delay(0.08, function() self.Entity.AdjustSpeed(chave, 1) end)
    self:Damage(hit.target, 10, { Hit = hit })
end,
`,
    desc: `O código acima pausa a animação por um instante no momento do acerto (o "peso" do golpe) e a devolve à velocidade normal.`,
  });

  X("api.Animation.AdjustWeight", {
    code: `
-- mancando: a animação de manco ganha peso conforme a vida cai
local peso = 1 - entity.GetHealthRatio()
entity.AdjustWeight("Manco", peso, 0.3)
`,
    desc: `O código acima mistura mais ou menos uma animação de manco conforme a vida. O peso vai de 0 a 1 e muda com fade de 0,3 s.`,
  });

  X("api.Animation.OnMarker", {
    code: `
onStart = function(self)
    local id = self.charLib.M1.M1Start
    self.Entity.PlayAnimation(id)
    self.Entity.OnMarker(tostring(id), "Hit", function() self:StartHitbox(0.15) end)
    self.Entity.OnMarker(tostring(id), "End", function() self:Stop(false) end)
end,
`,
    desc: `O código acima sincroniza o golpe com a animação: a hitbox liga no marcador <code>Hit</code> e a skill termina no marcador <code>End</code>. Os marcadores são os Animation Events postos no editor de animação. A chave é a da track (o ID, se você não passou outra no PlayAnimation).`,
  });

  X("api.Animation.WaitForMarker", {
    code: `
onStart = function(self)
    local id = self.charLib.S1.SpinStart
    self.Entity.PlayAnimation(id)
    task.spawn(function()
        if self.Entity.WaitForMarker(tostring(id), "Solta", 1.5) then
            self:Damage(self.alvo, 30)
        else
            self:Stop(true)   -- o marcador não veio a tempo
        end
    end)
end,
`,
    desc: `O código acima espera o marcador <code>Solta</code> por até 1,5 s numa thread separada (a função bloqueia quem a chama; nunca chame direto no <code>onStart</code>, que travaria o motor). Devolve <code>true</code> se o marcador chegou e <code>false</code> no timeout.`,
  });

  X("api.Animation.GetMarkerSignal", {
    code: `
local sinal = entity.GetMarkerSignal("Postura", "Passo")
if sinal then
    sinal:Connect(function() SoundManager.PlayOneShot3D(entity.GetPosition(), somDePasso) end)
end
`,
    desc: `O código acima conecta um som a cada marcador <code>Passo</code> da track. Diferente do <code>OnMarker</code>, a conexão fica com você (o componente não a desconecta no Destroy).`,
  });

  X("api.Animation.PlaySequence", {
    code: `
local lib = entity.GetLibCategory("S1")
entity.PlaySequence({
    { id = lib.SpinStart, key = "Giro" },                        -- avança quando acabar
    { id = lib.SpinLoop, key = "Giro", delay = 0.4 },            -- avança depois de 0,4 s
}, 1, { from = 2, to = 2, count = 5 })                           -- o passo 2 toca 5 vezes
`,
    desc: `O código acima toca a entrada do giro e depois o loop 5 vezes seguidas. Cada passo avança no marcador (<code>marker</code>), num tempo (<code>delay</code>) ou, sem nenhum dos dois, quando a animação termina. O terceiro argumento repete um trecho da sequência.`,
  });

  X("api.Animation.PlayFromLib", {
    code: `
entity.PlayFromLib("M1", "M1Start")              -- chave automática: "M1_M1Start"
entity.StopAnimation("M1_M1Start")
`,
    desc: `O código acima toca uma animação pela biblioteca do personagem da entidade (o <code>ChosenChar</code>), por conjunto e nome. A chave padrão é <code>conjunto_nome</code>. Numa skill, prefira <code>self.charLib</code>, que usa o kit dono da skill (uma skill roubada segue com as animações dela).`,
  });

  X("api.Animation.GetLibAnimId", {
    code: `
local id = entity.GetLibAnimId("S1", "SpinLoop")
if id then entity.PlayAnimation(id, "Giro") end
`,
    desc: `O código acima busca o ID de uma animação da biblioteca e a toca com uma chave própria. Conjunto ou nome inexistentes dão warn e <code>nil</code>.`,
  });

  X("api.Animation.GetLibCategory", {
    code: `
for nome, id in entity.GetLibCategory("M1") or {} do
    print(nome, id)
end
`,
    desc: `O código acima lista as animações do conjunto M1 do personagem. Útil para precarregar ou montar sequências.`,
  });

  X("api.Animation.GetTrack", {
    code: `
local track = entity.GetTrack("Giro")
if track then print(track.TimePosition, track.Length) end
`,
    desc: `O código acima lê a AnimationTrack da chave para consultar o tempo dela. A track sai do registro sozinha quando para.`,
  });

  X("api.Animation.IsPlaying", {
    code: `
if not entity.IsPlaying("Postura") then
    entity.PlayAnimation(idPostura, "Postura")
end
`,
    desc: `O código acima só toca a postura se ela não estiver tocando, para não reiniciar a animação a cada chamada.`,
  });

  X("api.Animation.GetAllTracks", {
    code: `
for chave, track in entity.GetAllTracks() do
    print(chave, track.Animation.AnimationId)
end
`,
    desc: `O código acima lista as tracks ativas por chave, para depuração ("por que o personagem está com duas animações?").`,
  });

  X("api.Animation.GetAnimationType", {
    code: `
if entity.GetAnimationType() == "Custom" then
    -- rig sem Humanoid (AnimationController)
end
`,
    desc: `O código acima confere se a entidade anima por Humanoid ou por AnimationController (rig customizado). As funções do componente funcionam igual nos dois.`,
  });

  // ================================================================ Control
  X("api.Control.Possess", [
    {
      t: "player assume uma torre",
      code: `
-- a torre precisa do componente Control (e Movement, se for andar)
if torre.Possess({ Player = player }) then
    print(player.Name, "está dirigindo a torre")
end
-- ...mais tarde
torre.Release()
`,
      desc: `O código acima passa o controle da torre para o player: o input dele (movimento, mira, skills) passa a ir para a torre, a IA dela é pausada e a barra de vida mostra a torre. O Release devolve tudo: o player volta ao corpo anterior e a IA volta a rodar.`,
    },
    {
      t: "controle mental de uma skill",
      code: `
onStart = function(self, ctx)
    local alvo = ctx.input.Target and DataManager.Get(ctx.input.Target)
    if not (alvo and self.Entity.Player and alvo:HasComponent(Component.Control)) then
        return self:Fizzle()
    end
    if alvo.Possess({ Player = self.Entity.Player }, { ReleaseOnDeath = true }) then
        self:Own(function() alvo.Release() end)
    end
end,
`,
      desc: `O código acima faz o player dirigir o alvo enquanto a skill durar. O <code>Own</code> garante a devolução em qualquer fim (duração, cancelamento, morte de quem casta), e <code>ReleaseOnDeath</code> devolve também se o possuído morrer. As possessões ficam numa pilha por player: soltar volta para o corpo anterior, não necessariamente para o original.`,
    },
  ]);

  X("api.Control.Release", {
    code: `
local soltou = torre.Release()
print(soltou)   -- false se ninguém de fora a dirigia
`,
    desc: `O código acima devolve a torre ao controlador nativo dela. Se um player a possuía, ele volta ao corpo anterior da pilha. Devolve <code>false</code> quando não havia possessão.`,
  });

  X("api.Control.Lock", {
    code: `
-- QTE: o player não controla nada até apertar a sequência certa
local entity = DataManager.Get(player)
entity.Lock()
esperarQTE(player)
entity.Unlock()
`,
    desc: `O código acima corta o input do player durante um QTE. O Lock corta a fonte sem trocar quem controla: num player, o input dele para na raiz; numa IA, o Brain é desligado. A entidade precisa do componente Control, e o player padrão do <code>Main.server</code> não tem: adicione com <code>AddComponent(Component.Control, {}, true)</code>, ou use ${L("api.GlobalAntiCheat.LockPlayerInput")} direto.`,
  });

  X("api.Control.Unlock", {
    code: `
entity.Lock()
task.delay(3, function() entity.Unlock() end)
`,
    desc: `O código acima devolve o controle depois de 3 segundos. O Unlock restaura exatamente o que o Lock cortou; uma possessão feita durante o Lock passa a valer no Unlock.`,
  });

  X("api.Control.GetController", {
    code: `
local c = npc.GetController()
if c.Player then
    print("dirigido por", c.Player.Name)
elseif c.AI then
    print("dirigido pela IA")
end
`,
    desc: `O código acima diz quem dirige a entidade agora: um player (<code>Player</code>) ou uma IA (<code>AI = true</code>).`,
  });

  X("api.Control.IsControlledBy", {
    code: `
if golem.IsControlledBy(player) then
    mostrarHUDdoGolem(player)
end
`,
    desc: `O código acima mostra a HUD especial só para o player que está dirigindo o golem.`,
  });

  X("api.Control.IsAIControlled", {
    code: `
-- só NPCs dirigidos pela IA entram na contagem de inimigos da onda
if e:HasComponent(Component.Control) and e.IsAIControlled() then
    restantes += 1
end
`,
    desc: `O código acima conta só os inimigos que a IA dirige (um possuído por um player fica de fora).`,
  });

  X("api.Control.LinkTo", {
    code: `
-- marionetista: o boneco anda e mira junto com o player
local mestre = DataManager.Get(player)
mestre.LinkTo(boneco, { MirrorMovement = true, MirrorLook = true })
`,
    desc: `O código acima faz o boneco receber o mesmo input de movimento e de mira que o player. As skills não são espelhadas, só os eixos. As duas entidades precisam do componente Control (o player padrão não tem: adicione com <code>AddComponent</code>).`,
  });

  X("api.Control.Unlink", {
    code: `
mestre.Unlink(boneco)
`,
    desc: `O código acima desfaz o link: o boneco para de receber o input do player.`,
  });

  X("api.Control.GetLinkedEntities", {
    code: `
for _, e in mestre.GetLinkedEntities("MirrorMovement") do
    print("anda junto:", e.ID)
end
`,
    desc: `O código acima lista as entidades que andam junto com o mestre. Sem filtro, todas as linkadas.`,
  });
})();

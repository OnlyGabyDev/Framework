/*
  Exemplos de uso: componentes (1/2): Character, Health, Status, Attributes, AI, Affiliation.
  Estilo e requires: ver o topo de 09-exemplos-nucleo.js.
*/
(function () {
  var X = DOCS.example;

  // ================================================================ Character
  X("api.Character.GetModel", {
    code: `
-- destaca de vermelho, por 1 s, quem entra na zona
zona:OnEnter(function(e)
    local model = e.GetModel()
    if not model then return end
    local destaque = Instance.new("Highlight")
    destaque.FillColor = Color3.fromRGB(255, 60, 60)
    destaque.Parent = model
    task.delay(1, destaque.Destroy, destaque)
end)
`,
    desc: `O código acima marca com um Highlight, por um segundo, o Model de cada entidade que entra numa zona. <code>GetModel</code> devolve o mesmo que <code>entity.Instance</code>; numa entidade só de dado os dois são <code>nil</code>, mas ela nem tem Character.`,
  });

  X("api.Character.GetRoot", {
    code: `
onHit = function(self, hit)
    -- agarra o alvo na frente de quem casta, 4 studs adiante
    local release = hit.target.AttachTo(self.Entity.GetRoot(), CFrame.new(0, 0, -4))
    if release then self:Own(release) end
end,
`,
    desc: `O código acima prende o alvo atingido ao root de quem casta. A peça raiz é a <code>HumanoidRootPart</code> ou, num rig sem Humanoid, a <code>PrimaryPart</code> do Model; é a peça que se move, que gira e que as Forces empurram, e por isso é a referência de agarrão, de distância e de mira.`,
  });

  X("api.Character.GetHumanoid", {
    code: `
alvo:Listen({
    Role = Enum.Roles.IN, Breakpoint = Enum.Breakpoints.OnDeath,
    Action = function()
        local humanoid = alvo.GetHumanoid()
        if humanoid then humanoid.Health = 0 end   -- o motor não mata o Humanoid
    end,
})
`,
    desc: `O código acima derruba o Humanoid quando a entidade morre. O framework não mexe no Humanoid na morte, de propósito: o HP do motor e o do Humanoid são coisas separadas, e o que acontece com o corpo (ragdoll, animação, respawn) é decisão do jogo. Em rig sem Humanoid, <code>GetHumanoid</code> devolve <code>nil</code>.`,
  });

  X("api.Character.GetPosition", {
    code: `
local function maisProximo(origem, candidatos, alcance)
    local melhor, melhorDist = nil, alcance
    for _, e in candidatos do
        local dist = (e.GetPosition() - origem.GetPosition()).Magnitude
        if dist < melhorDist then melhor, melhorDist = e, dist end
    end
    return melhor
end
`,
    desc: `O código acima acha, numa lista de entidades, a mais próxima de <code>origem</code> dentro do alcance. <code>GetPosition</code> é a posição do root; sem root (corpo ainda carregando) devolve <code>Vector3.zero</code>, em vez de dar erro.`,
  });

  X("api.Character.GetCFrame", {
    code: `
onStart = function(self)
    -- uma onda que nasce 3 studs à frente de quem casta, virada para onde ele olha
    local origem = self.Entity.GetCFrame() * CFrame.new(0, 0, -3)
    local hitbox, carrier = Presets.ExpandingCone(self.Entity, origem, "X", 30, 12, 0.3)
    hitbox:OnHit(function(result)
        local e = DataManager.GetEntityFromInstance(result.Instance)
        if e and StateTable.CanAffect(self, e) then self:Damage(e, 15) end
    end)
end,
`,
    desc: `O código acima usa o CFrame do root como origem de uma hitbox: multiplicar por <code>CFrame.new(0, 0, -3)</code> anda 3 studs para a frente no espaço do personagem (o -Z é a frente no Roblox). Use <code>GetCFrame</code> sempre que precisar da orientação, não só da posição.`,
  });

  X("api.Character.Teleport", {
    code: `
local checkpoint = workspace.Checkpoints.Fase2

local entity = DataManager.Get(player)
if entity then
    entity.Teleport(checkpoint.Position + Vector3.new(0, 4, 0))
end
`,
    desc: `O código acima leva o player até um checkpoint, 4 studs acima da peça para não nascer dentro dela. O corpo do player é simulado pelo cliente, mas uma escrita de CFrame no root feita pelo servidor (o Teleport é uma) abre a janela de confiança do anti-cheat, então a validação de movimento não puxa o player de volta. O teleporte usa <code>CFrame.new(posição)</code>: o corpo perde a rotação que tinha.`,
  });

  X("api.Character.GetCharacterWrapper", {
    code: `
local wrapper = npc.GetCharacterWrapper()
print(wrapper:GetRoot(), npc.GetHumanoid() ~= nil)
-- HumanoidRootPart  false   (rig sem Humanoid: anda pelo ForceRig)
`,
    desc: `O código acima lê o wrapper de corpo, a camada que esconde a diferença entre um corpo com Humanoid e um rig sem Humanoid. O jogo quase nunca precisa dele (as funções de Character e Movement já usam o wrapper por dentro); serve para depuração e para quem escreve um componente novo que mexe no corpo.`,
  });

  X("api.Character.SetEntity", {
    code: `
-- o que o DataManager faz por você, depois de criar os componentes:
if core:HasComponent(Component.Character) then
    core.SetEntity(model)            -- NPC: o Model
    -- core.SetEntity({ Model = character, Player = player })   -- player
end
`,
    desc: `O código acima mostra o passo interno em que o DataManager liga o corpo ao componente Character (acha o root e o Humanoid e cria o wrapper). Uma segunda chamada devolve <code>false</code> e não troca nada: para outro corpo, crie outra entidade.`,
  });

  // ================================================================ Health
  X("api.Health.TakeDamage", [
    {
      t: "dano de ambiente",
      code: `
local lava = workspace.Lava

local zona = AreaEffect.new(function() return lava.CFrame end, "Box", lava.Size, 4)
zona:OnStay(function(e)
    if e:HasComponent(Component.Health) then
        e.TakeDamage(5)   -- sem fonte: ninguém leva o crédito
    end
end)
zona:Start()
`,
      desc: `O código acima tira 5 de vida, 4 vezes por segundo, de quem estiver em cima da lava. Sem fonte (o 2º argumento), o dano ainda passa por imunidade, bloqueio, Defense/Armor e pelos listeners do alvo, mas não há atacante: nenhum <span class="badge out">OUT</span> <code>OnDamage</code> é emitido e a morte não credita ninguém.`,
    },
    {
      t: "dano de um status, com crédito",
      code: `
-- dentro de um status de queimadura (onStep)
onStep = function(self, dt)
    self.t = (self.t or 0) + dt
    if self.t < 0.5 then return end
    self.t = 0
    local ok, dano = self.Entity.TakeDamage(self.data.damage, self.Runner)
    if not ok then return end   -- iFrame, morto, cancelado no PreDamage...
end,
`,
      desc: `O código acima é o tique de um dano periódico. O runner do status é passado como fonte: o contexto ganha as traits do status (ex.: DOT, para escudos e listeners filtrarem) e o crédito vai para quem aplicou a queimadura, não para a vítima onde o status roda. O retorno é <code>true, danoReal, ctx</code> quando o dano entrou, ou <code>false, motivo</code>.`,
    },
  ]);

  X("api.Health.Heal", [
    {
      t: "cura simples",
      code: `
-- poção: cura 40, sem passar do máximo
local subiu = entity.Heal(40)
print("curou", subiu)
`,
      desc: `O código acima cura até 40 de vida, sem passar de <code>HealCap × MaxHP</code> (o padrão do HealCap é 1, ou seja, o máximo). O retorno é quanto o HP subiu de fato: com 90/100 de vida, a poção devolve 10.`,
    },
    {
      t: "cura de aliado, com sobrevida e crédito",
      code: `
-- data.affects = { Ally = true, Enemy = false }: a hitbox entrega só aliados
onHit = function(self, hit)
    hit.target.Heal(30, {
        Source = self.Runner,   -- o dono recebe OUT.OnHeal (placar de cura)
        Cap = 1.25,             -- pode passar do máximo até 125%
        Traits = { "Sagrado" },
    })
end,
`,
      desc: `O código acima cura em 30 cada aliado que a hitbox da skill tocar, permitindo sobrevida até 125% do MaxHP. Por padrão a hitbox não entrega aliados; o <code>data.affects</code> da skill inverte isso. Com <code>Source</code>, quem curou recebe o <span class="badge out">OUT</span> <code>OnHeal</code> com <code>ctx.actualHeal</code>; as <code>Traits</code> entram no contexto, e um listener <span class="badge in">IN</span> <code>OnHeal</code> do alvo pode filtrar por elas (uma maldição que corta curas "Sagrado", por exemplo). A cura nunca reduz o HP: quem já está acima do teto fica onde está.`,
    },
  ]);

  X("api.Health.Die", {
    code: `
-- execução: abaixo de 10% de vida, o golpe mata
onHit = function(self, hit)
    local alvo = hit.target
    if alvo.GetHealthRatio() < 0.1 then
        alvo.Die(self.Runner)
    else
        self:Damage(alvo, 20, { Hit = hit })
    end
end,
`,
    desc: `O código acima mata na hora um alvo com menos de 10% de vida. <code>Die</code> pula o pipeline de dano (imunidade, bloqueio, PreDamage): use para execução, queda no vazio, fim de tempo. Com o runner como <code>killer</code>, o <span class="badge out">OUT</span> <code>OnDeath</code> vai para quem executou, como numa morte normal.`,
  });

  X("api.Health.Revive", {
    code: `
-- totem de ressurreição: revive o aliado com 30% da vida
local function reviver(aliado)
    if aliado.IsAlive() then return end
    aliado.Revive(aliado.GetMaxHP() * 0.3)
end
`,
    desc: `O código acima revive um aliado morto com 30% do máximo. O valor passado é o HP exato (sem corte no MaxHP); sem valor, volta com a vida cheia. O <span class="badge in">IN</span> <code>OnRevive</code> é emitido, e o jogo cuida do corpo (levantar o Humanoid, tocar a animação). Revive numa entidade viva devolve <code>false</code>.`,
  });

  X("api.Health.GetHP", {
    code: `
local function textoDeVida(e)
    return string.format("%d / %d", math.floor(e.GetHP()), math.floor(e.GetMaxHP()))
end

print(textoDeVida(chefe))   -- 4870 / 5000
`,
    desc: `O código acima monta o texto "atual / máximo" de uma barra de vida. O HP é um número com casas decimais (multiplicadores e porcentagens geram frações), então arredonde só na hora de mostrar.`,
  });

  X("api.Health.GetMaxHP", {
    code: `
-- "cura 15% da vida máxima"
entity.Heal(entity.GetMaxHP() * 0.15)
`,
    desc: `O código acima cura 15% da vida máxima. Com o componente Attributes, o MaxHP é o stat <code>MaxHP</code> com os modificadores ativos (um buff de +20% de vida já entra na conta); sem Attributes, é o <code>MaxHP</code> do config do Health.`,
  });

  X("api.Health.SetHP", {
    code: `
-- desafio "1 HP": todo mundo começa a rodada com 1 de vida
for _, player in game.Players:GetPlayers() do
    local e = DataManager.Get(player)
    if e then e.SetHP(1) end
end
`,
    desc: `O código acima deixa cada player com exatamente 1 de vida. <code>SetHP</code> define o valor exato: não passa pelo pipeline de dano nem tem corte no MaxHP (<code>SetHP(150)</code> com máximo 100 deixa 150). Subir o HP emite <span class="badge in">IN</span> <code>OnHeal</code>; 0 ou menos mata.`,
  });

  X("api.Health.SetMaxHP", {
    code: `
-- fase 2 do chefe: ao cruzar 50% de vida, o máximo dobra (uma vez só)
local desinscrever
desinscrever = chefe:Listen({
    Role = Enum.Roles.IN, Breakpoint = Enum.Breakpoints.PostDamage,
    Action = function()
        if chefe.GetHealthRatio() <= 0.5 then
            desinscrever()
            chefe.SetMaxHP(chefe.GetMaxHP() * 2)
        end
    end,
})
`,
    desc: `O código acima dobra a vida máxima do chefe quando ele cai para metade da vida. <code>SetMaxHP</code> mantém a proporção: o chefe continua com 50%, agora do máximo novo (5000 de 10000, em vez de 2500 de 5000). Com Attributes, o valor vira a base do stat <code>MaxHP</code>. A reação se desinscreve dentro do <code>if</code>, para disparar uma vez só.`,
  });

  X("api.Health.GetHealthRatio", {
    code: `
-- golpe que bate mais forte em alvo ferido
onHit = function(self, hit)
    local bonus = 1 + (1 - math.min(hit.target.GetHealthRatio(), 1))   -- até 2x
    self:Damage(hit.target, 20 * bonus, { Hit = hit })
end,
`,
    desc: `O código acima aumenta o dano conforme a vida do alvo cai: o dobro num alvo quase morto. <code>GetHealthRatio</code> é HP ÷ MaxHP e pode passar de 1 com sobrevida; o <code>math.min</code> evita bônus negativo nesse caso.`,
  });

  X("api.Health.IsAlive", {
    code: `
local function brain(entity, dt)
    local alvo = entity.alvoAtual
    if not alvo or not alvo.Active or not alvo.IsAlive() then
        entity.alvoAtual = acharNovoAlvo(entity)
        return
    end
    -- persegue o alvo...
end
`,
    desc: `O código acima faz uma IA trocar de alvo quando o atual morre ou sai do jogo. <code>Active</code> diz se a entidade ainda existe; <code>IsAlive</code> diz se ela está viva (uma entidade morta continua ativa até ser removida ou revivida).`,
  });

  X("api.Health.GetDamageHistory", {
    code: `
alvo:Listen({
    Role = Enum.Roles.IN, Breakpoint = Enum.Breakpoints.OnDeath,
    Action = function()
        for i, registro in alvo.GetDamageHistory() do
            local quem = registro.source and registro.source.skillName or "ambiente"
            print(i, quem, registro.amount, os.clock() - registro.time)
        end
    end,
})
`,
    desc: `O código acima imprime, na morte, os últimos danos que a entidade levou (o mais recente primeiro), com a skill que causou cada um. O histórico guarda só os 10 últimos registros: serve para tela de morte ("morto por...") e depuração, não para estatística da partida inteira. O campo <code>time</code> é <code>tick()</code>.`,
  });

  X("api.Health.GetTotalDamageTaken", {
    code: `
-- IA do chefe: apanhou muito nos últimos golpes, foge para se curar
local function brain(entity, dt)
    if entity.GetTotalDamageTaken() > 300 and not entity.fugindo then
        entity.fugindo = true
        comecarFuga(entity)
    end
end
`,
    desc: `O código acima faz um chefe fugir quando os últimos golpes somam mais de 300 de dano. Atenção: a soma é só do histórico (os 10 últimos danos), não da vida inteira da entidade, o que serve bem para "apanhou muito agora". Para o total da partida, some num listener <code>PostDamage</code>.`,
  });

  X("api.Health.SyncHealthHUD", {
    code: `
-- depois de trocar o player de corpo por um caminho próprio do jogo
AntiCheat.SetControlledEntity(player, golem.ID)
golem.SyncHealthHUD()   -- a barra passa a mostrar a vida do golem
`,
    desc: `O código acima reenvia a barra de vida para quem dirige o corpo agora. O Health já manda a vida a cada mudança e a possessão (${L("api.Control.Possess", "Possess")}) já chama isto na troca; só é preciso chamar à mão quando o jogo redireciona o controle por fora do Control.`,
  });

  // ================================================================ Status
  X("api.Status.ApplyStatus", [
    {
      t: "estado com duração",
      code: `
-- armadilha de urso: prende quem pisa por 2 s
zona:OnEnter(function(e)
    if e:HasComponent(Component.Status) then
        e.ApplyStatus(StateTable.States.Root, 2)   -- forma curta: só a duração
    end
end)
`,
      desc: `O código acima aplica o estado Root por 2 segundos em quem entra na zona. O segundo argumento pode ser só a duração; o Root desliga a tag <code>canMove</code> enquanto durar. Sem <code>Source</code>, ninguém leva crédito pelo que o status fizer.`,
    },
    {
      t: "guardar o ID e remover depois",
      code: `
onStart = function(self)
    -- trava o próprio movimento enquanto a skill carrega
    self.travaID = self.Entity.ApplyStatus(StateTable.States.NoControl, {
        Duration = self.data.duration,
        Source = self.Runner,
    })
end,
onEnd = function(self)
    if self.travaID then self.Entity.RemoveStatusByID(self.travaID) end
end,
`,
      desc: `O código acima aplica um NoControl na própria entidade durante a skill e o remove no fim, por qualquer motivo (o <code>onEnd</code> sempre roda). Guardar o ID e remover por ele garante que só esta aplicação sai: outra skill que tenha aplicado NoControl ao mesmo tempo não é afetada. O retorno é <code>nil</code> se o status não entrou (morto, escudo, cooldown de reaplicação, cancelado no <code>PreApplyStatus</code>).`,
    },
  ]);

  X("api.Status.RemoveStatusByID", {
    code: `
local id = alvo.ApplyStatus(StateTable.States.Stun, { Duration = 5, Source = runner })

-- o aliado usou "purificar" antes do fim
if id then
    local saiu = alvo.RemoveStatusByID(id)
    print(saiu)   -- true (false se já tinha acabado)
end
`,
    desc: `O código acima remove uma aplicação específica de Stun antes do fim. É a forma recomendada de remover: atinge só a aplicação deste ID, mesmo que haja outros Stuns de outras fontes na entidade.`,
  });

  X("api.Status.RemoveStatus", {
    code: `
-- "purificar": tira todo sangramento e veneno, de qualquer fonte
for _, nome in { "Bleed", "Poison" } do
    alvo.RemoveStatus(nome)
end
`,
    desc: `O código acima remove todas as instâncias de dois status pelo nome (o <code>data.name</code>), não importa quem os aplicou. Use para limpezas gerais; para desfazer a sua própria aplicação, prefira ${L("api.Status.RemoveStatusByID")}. Status não pode recusar a remoção.`,
  });

  X("api.Status.RemoveAmount", {
    code: `
-- cada cura tira 2 stacks de sangramento
alvo:Listen({
    Role = Enum.Roles.IN, Breakpoint = Enum.Breakpoints.OnHeal,
    Action = function()
        alvo.RemoveAmount("Bleed", 2)
    end,
})
`,
    desc: `O código acima reduz em 2 os stacks de Bleed a cada cura. Num status com <code>stackOnSelf</code> (como o Bleed), diminui o contador da instância e a encerra se chegar a zero; num empilhável de instâncias separadas, encerra as 2 mais antigas. Só vale para status (não para estados como Stun).`,
  });

  X("api.Status.GetStatus", {
    code: `
local entradas = alvo.GetStatus("Bleed")
if entradas then
    local bleed = entradas[1]
    print(bleed.ID, bleed.runner.skill.counter, bleed.runner:IsEnded())
end
`,
    desc: `O código acima lê a entrada ativa do Bleed: o ID da aplicação, os stacks (o <code>counter</code> da instância) e o runner. O retorno é sempre uma lista (mesmo com uma entrada só) ou <code>nil</code> se o status não está ativo; procura nos dois grupos, status e estados.`,
  });

  X("api.Status.GetStatusCounter", {
    code: `
-- golpe final: consome os stacks de sangramento e causa dano por stack
onHit = function(self, hit)
    local stacks = hit.target.GetStatusCounter("Bleed")
    if stacks > 0 then
        hit.target.RemoveStatus("Bleed")
        self:Damage(hit.target, 8 * stacks, { Hit = hit })
    end
end,
`,
    desc: `O código acima transforma os stacks de Bleed do alvo em dano imediato. <code>GetStatusCounter</code> devolve os stacks de um status <code>stackOnSelf</code>, ou o número de instâncias de um empilhável comum, e 0 se o status não está ativo.`,
  });

  X("api.Status.GetActiveTags", {
    code: `
local tags, donos = alvo.GetActiveTags()

if tags[Enum.Tags.canMove] == false then
    local quem = donos[Enum.Tags.canMove]
    print("preso por", quem and quem.runner and quem.runner.skillName)
end
if tags[Enum.Tags.iFrame] then
    print("invulnerável agora")
end
`,
    desc: `O código acima pergunta se o alvo está preso e quem o prendeu, e se está invulnerável. As tags vêm combinadas de todos os status ativos, com <code>false</code> vencendo; uma tag que nenhum status declara fica <code>nil</code> (o padrão está em <code>Enum.tagsBase</code>). O segundo retorno diz, para cada tag ligada, a aplicação mais recente que a liga.`,
  });

  X("api.Status.GetActiveStates", {
    code: `
for nome, entrada in alvo.GetActiveStates() do
    print("estado ativo:", nome)
end
`,
    desc: `O código acima lista os estados ativos (Stun, Root, Silence, NoControl). O valor de cada nome é a entrada do estado, ou uma lista de entradas se houver mais de uma aplicação.`,
  });

  X("api.Status.HasStateCategory", {
    code: `
-- "golpe covarde": dano dobrado em quem está atordoado
onHit = function(self, hit)
    local mult = hit.target.HasStateCategory(Enum.States.Stun) and 2 or 1
    self:Damage(hit.target, 15 * mult, { Hit = hit })
end,
`,
    desc: `O código acima dobra o dano contra alvos com algum estado da categoria Stun. A pergunta é pela <code>category</code> do estado, não pelo nome: um estado novo seu com <code>category = Enum.States.Stun</code> também conta.`,
  });

  X("api.Status.ValidateHit", {
    code: `
-- prever se um golpe vai ser ignorado, antes de tocar a animação de acerto
local ctx = StateTable.BuildContext(self.Runner, 20)
local pode, motivo = alvo.ValidateHit(ctx)
if not pode then
    print("imune por", motivo)   -- iFrame
end
`,
    desc: `O código acima consulta a imunidade do alvo para um hit com as traits desta skill. É a mesma checagem que o <code>TakeDamage</code> faz; chamar à mão só serve para prever (tocar um "MISS", por exemplo). O segundo retorno é a tag que barrou.`,
  });

  X("api.Status.ApplyMitigation", {
    code: `
-- simular quanto de um golpe passaria pelo bloqueio atual
local ctx = StateTable.BuildContext(self.Runner, 50)
alvo.ApplyMitigation(ctx)
print(ctx.damage)   -- 20 com uma Muralha de 60%; 50 sem bloqueio
`,
    desc: `O código acima aplica no contexto o bloqueio que o alvo tem agora. Cuidado: a função age de verdade (pode quebrar o bloqueio com BlockBreak e roda o <code>onTrigger</code> do status de bloqueio), então use só se a sua mecânica aceitar esses efeitos; o <code>TakeDamage</code> já chama isto sozinho.`,
  });

  X("api.Status.GetImmunityRules", {
    code: `
for tag, regra in alvo.GetImmunityRules() do
    print(tag, "furada por:", table.concat(regra.bypassableBy, ", "))
end
-- iFrame  furada por: TrueHit
`,
    desc: `O código acima lista as tags de imunidade conhecidas e as traits que furam cada uma. As regras são calculadas uma vez para o servidor, a partir do <code>bypassBy</code> de todos os status; são iguais em toda entidade.`,
  });

  X("api.Status.GenerateUniqueEffectID", {
    code: `
-- reservar o ID antes de aplicar (para registrar em outra estrutura)
local id = alvo.GenerateUniqueEffectID("Marca")
marcas[id] = { dono = self.Entity }
alvo.ApplyStatus(statusDaMarca, { Duration = 8, Source = self.Runner, ID = id })
`,
    desc: `O código acima gera um ID antes de aplicar o status e o passa no <code>ID</code> das opções, para usá-lo como chave numa tabela própria. Sem <code>ID</code>, o ApplyStatus gera um igual sozinho e o devolve.`,
  });

  X("api.Status.HasStatusCooldown", {
    code: `
if alvo.HasStatusCooldown("Stun") then
    print("ainda imune a Stun por", alvo.GetStatusCooldown("Stun"), "s")
end
`,
    desc: `O código acima consulta o cooldown de reaplicação de um status. Ele existe quando o status declara <code>data.cooldown</code> (ou quando alguém chama ${L("api.Status.SetStatusCooldown")}): enquanto durar, um novo ApplyStatus desse nome é recusado.`,
  });

  X("api.Status.SetStatusCooldown", {
    code: `
-- "resistência a controle": depois de sair de um Stun, 3 s sem poder levar outro
alvo:Listen({
    Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.onEnd,
    Action = function(ctx)
        local r = ctx.sourceRunner
        if r and r.skillName == "Stun" then
            alvo.SetStatusCooldown("Stun", 3)
        end
    end,
})
`,
    desc: `O código acima dá 3 segundos de imunidade a Stun depois que um Stun termina. O fim de qualquer runner (skill ou status) emite <span class="badge out">OUT</span> <code>onEnd</code> na entidade dona, com o runner em <code>ctx.sourceRunner</code>; o nome do runner de status é o <code>data.name</code>.`,
  });

  X("api.Status.GetStatusCooldown", {
    code: `
local restante = alvo.GetStatusCooldown("Stun")
if restante > 0 then
    mostrarIcone(alvo, "ResistenciaStun", restante)
end
`,
    desc: `O código acima mostra um ícone de resistência enquanto o cooldown de reaplicação do Stun durar. O retorno são os segundos restantes, e 0 quando não há cooldown.`,
  });

  // ================================================================ Attributes
  X("api.Attributes.GetStat", {
    code: `
local vel = entity.GetStat(Enum.Stats.Speed, Enum.StatDefaults.Speed)
local mana = entity.GetStat("Mana", 0)        -- stat do jogo, com padrão
print(vel, mana)
`,
    desc: `O código acima lê a velocidade final (base, modificadores e limite) e um stat próprio do jogo. O segundo argumento é o valor usado quando a entidade não tem base registrada para o stat; sem ele, o padrão é 0.`,
  });

  X("api.Attributes.SetStat", {
    code: `
-- subir de nível: +10% de vida e +2 de Defense na base
local nivel = entity.GetStat("Nivel", 1) + 1
entity.SetStat("Nivel", nivel)
entity.SetStat(Enum.Stats.Defense, entity.GetStat(Enum.Stats.Defense) + 2)
entity.SetMaxHP(entity.GetMaxHP() * 1.1)
`,
    desc: `O código acima grava stats de base. <code>SetStat</code> troca a base e mantém os modificadores ativos por cima. Para o MaxHP use <code>SetMaxHP</code>, que também ajusta o HP atual na mesma proporção.`,
  });

  X("api.Attributes.GetStats", {
    code: `
local forma = entity.GetStats()
print(forma.Stats.Speed, forma.Weapon)   -- 20  Martelo   (Schema, forma Base)
`,
    desc: `O código acima lê a tabela da forma atual do personagem no CharacterDatabase (Stats, Loadout, Weapon). São os valores de projeto da forma, não os stats atuais: para o valor em jogo, com buffs, use ${L("api.Attributes.GetStat")}. Sem Combat, devolve <code>{ Stats = Enum.StatDefaults }</code>.`,
  });

  X("api.Attributes.AddModifier", [
    {
      t: "lentidão de uma zona",
      code: `
zona:OnEnter(function(e)
    e.AddModifier(Enum.Stats.Speed, zona.ID, Enum.ModifierType.MultPercent, 0.6)
end)
zona:OnExit(function(e)
    e.RemoveModifier(Enum.Stats.Speed, zona.ID)
end)
`,
      desc: `O código acima deixa quem está dentro da zona com 60% da velocidade. O ID da origem (aqui, o da zona) identifica o modificador: o mesmo ID adicionado duas vezes precisa de duas remoções, então duas zonas iguais não se anulam ao sair de uma só.`,
    },
    {
      t: "buff de status",
      code: `
-- StateTable/Status/Buffs/Furia.luau
return {
    data = { name = "Furia", category = Enum.Categories.Buff, duration = 6 },
    callbacks = {
        onStart = function(self)
            self.Entity.AddModifier(Enum.Stats.DamageMult, self.ID, Enum.ModifierType.AddPercent, 0.3)
            self.Entity.AddModifier(Enum.Stats.Speed, self.ID, Enum.ModifierType.Flat, 4)
        end,
        onEnd = function(self)
            self.Entity.RemoveModifier(Enum.Stats.DamageMult, self.ID)
            self.Entity.RemoveModifier(Enum.Stats.Speed, self.ID)
        end,
    },
}
`,
      desc: `O código acima é um buff de 6 segundos com +30% de dano e +4 de velocidade. Usar o <code>self.ID</code> da aplicação como origem faz cada aplicação ter o próprio modificador. A fórmula final é <code>((base + Flat) × (1 + soma dos AddPercent)) × produto dos MultPercent</code>; um Override troca a base (o menor Override vence).`,
    },
  ]);

  X("api.Attributes.RemoveModifier", {
    code: `
local origem = "Escudo_" .. self.Entity.ID
alvo.AddModifier(Enum.Stats.Defense, origem, Enum.ModifierType.Flat, 25)
task.delay(5, function()
    if alvo.Active then alvo.RemoveModifier(Enum.Stats.Defense, origem) end
end)
`,
    desc: `O código acima dá +25 de Defense por 5 segundos. <code>RemoveModifier</code> tira uma referência do modificador dessa origem; ele só sai de vez quando todas as referências adicionadas forem removidas. O <code>alvo.Active</code> evita mexer numa entidade que já saiu.`,
  });

  // ================================================================ AI
  X("api.AI.SetBrain", {
    code: `
local function patrulhar(entity, dt) --[[ anda entre pontos ]] end
local function perseguir(entity, dt) --[[ vai atrás do alvo e ataca ]] end

npc.SetBrain(patrulhar)

-- viu um player: muda de comportamento
npc.SetBrain(perseguir)
`,
    desc: `O código acima troca o comportamento de um NPC trocando a função de cérebro. O Brain é chamado a cada Heartbeat com <code>(entity, dt)</code>; uma máquina de estados simples é só trocar a função conforme a situação.`,
  });

  X("api.AI.GetBrain", {
    code: `
-- confusão: anda à toa por 3 s e depois volta ao normal
local original = npc.GetBrain()
npc.SetBrain(function(entity) SkillHandler.HandleMovementInput(entity.ID, direcaoAleatoria()) end)
task.delay(3, function()
    if npc.Active then npc.SetBrain(original) end
end)
`,
    desc: `O código acima guarda o cérebro atual, põe um temporário e devolve o original depois de 3 segundos. É o mesmo padrão que a possessão usa para devolver a IA ao NPC.`,
  });

  X("api.AI.SetEnabled", {
    code: `
-- cutscene: todos os NPCs param
for _, e in npcs do e.SetEnabled(false) end
tocarCutscene()
for _, e in npcs do e.SetEnabled(true) end
`,
    desc: `O código acima pausa os cérebros durante uma cutscene. Desligar não para o NPC no lugar se ele estava andando: a última direção mandada continua valendo; mande <code>HandleMovementInput(id, Vector3.zero)</code> antes, se precisar.`,
  });

  X("api.AI.IsAIEnabled", {
    code: `
if not npc.IsAIEnabled() then
    print(npc.ID, "está com a IA pausada (cutscene ou possessão)")
end
`,
    desc: `O código acima confere se o Brain do NPC está ligado. Um player possuindo o NPC pausa a IA dele; o Release devolve o estado anterior.`,
  });

  // ================================================================ Affiliation
  X("api.Affiliation.GetTeam", {
    code: `
local function mesmoTime(a, b)
    return a:HasComponent(Component.Affiliation) and b:HasComponent(Component.Affiliation)
        and a.GetTeam() == b.GetTeam()
end
`,
    desc: `O código acima compara os times de duas entidades. Para regras de alvo prefira ${L("api.StateTable.Relation")} e ${L("api.StateTable.CanAffect")}, que já tratam a entidade sem time (Neutral) e a própria entidade (Self).`,
  });

  X("api.Affiliation.SetTeam", {
    code: `
-- controle mental: o alvo luta do seu lado por 8 s
local timeOriginal = alvo.GetTeam()
alvo.SetTeam(self.Entity.GetTeam())
self:Own(function()
    if alvo.Active then alvo.SetTeam(timeOriginal) end
end)
`,
    desc: `O código acima muda o time do alvo enquanto a skill dura e o devolve no fim, por qualquer motivo (o <code>Own</code> roda no fim do runner). Como hitboxes e zonas perguntam a relação na hora do acerto, a troca vale imediatamente.`,
  });
})();

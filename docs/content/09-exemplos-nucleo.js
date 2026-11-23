/*
  Exemplos de uso: núcleo (DataManager, EntityCore).

  Estilo (o do manual do GameMaker): cada exemplo é um trecho em contexto, como ele apareceria num
  script do jogo, seguido do parágrafo que começa com "O código acima...". O parágrafo diz o que o
  trecho faz e o que não é óbvio (um retorno nil, um efeito colateral, o motivo de um argumento).
  Funções importantes têm mais de um exemplo, do básico para o completo.
  Requires que os exemplos supõem: DataManager, Component, StateTable e Enum = StateTable.Enum
  (ver a página "Referência da API").
*/
(function () {
  var X = DOCS.example;

  // ================================================================ DataManager
  X("api.DataManager.Create", [
    {
      t: "boneco de treino",
      code: `
local boneco = workspace.Dummies.Alvo   -- um Model com HumanoidRootPart (ou PrimaryPart)

local entity = DataManager.Create(boneco, {
    Component.Character, Component.Health, Component.Status,
}, {
    Health = { MaxHP = 500 },
})

if entity then
    print(entity.ID, entity.GetHP())   -- Entity_123456  500
end
`,
      desc: `O código acima transforma um Model do workspace numa entidade com corpo, vida e status, com 500 de vida máxima. O ID gerado também é gravado no atributo <code>EntityID</code> do Model, e é por ele que hitboxes, zonas e input acham a entidade depois. Se o primeiro argumento não for um Model (ou <code>{ Model, Player }</code>), o Create devolve <code>nil</code> e não registra nada; por isso o <code>if entity</code>.`,
    },
    {
      t: "chefe sem personagem, com kit montado em código",
      code: `
local Keys = require(game.ServerStorage.DataBase.SkillDatabase).Keys
local Intents = require(game.ReplicatedStorage.Input.Intents)

local chefe = DataManager.Create(workspace.Chefe, {
    Component.Character, Component.Health, Component.Status, Component.Movement,
    Component.Attributes, Component.Combat, Component.Affiliation, Component.AI,
}, {
    Health = { MaxHP = 5000, HealCap = 1.2 },
    Attributes = { BaseStats = { Speed = 12, DamageMult = 1.5 } },
    Combat = { ChosenChar = false },        -- sem kit do CharacterDatabase
    Affiliation = { Team = "Chefes" },
    AI = { Brain = brainDoChefe },
})

chefe.EquipSkill(Intents.Id.Dash, Keys.Schema.Dash)    -- skill do banco
chefe.EquipSkill(Intents.Id.Primary, socoDoChefe)      -- skill em tabela, escrita no próprio script
`,
      desc: `O código acima cria um chefe dirigido por IA, num time próprio, sem personagem do banco: com <code>ChosenChar = false</code> o loadout nasce vazio e as skills são equipadas depois, uma a uma (do banco ou em tabela). Repare que ele não tem Weapon nem Animation: uma skill que declare <code>requires</code> desses componentes, como o M1 da Schema, seria recusada no cast. Os stats vêm do <code>BaseStats</code> do config (sem ele, viriam da forma do personagem). O player não passa por aqui: o <code>Main.server</code> já chama <code>DataManager.Create({ Model = character, Player = player }, ...)</code> a cada spawn.`,
    },
  ]);

  X("api.DataManager.CreateData", {
    code: `
-- uma carta no tabuleiro: vida, status e atributos, mas nenhum corpo
local carta = DataManager.CreateData({ Component.Health, Component.Status, Component.Attributes }, {
    Health = { MaxHP = 3 },
    Attributes = { BaseStats = { Custo = 2, Ataque = 4 } },
})

carta.TakeDamage(1)
print(carta.GetHP(), carta.GetStat("Ataque"))   -- 2  4
print(carta.Instance)                           -- nil

-- a carta foi descartada
DataManager.Remove(carta)
`,
    desc: `O código acima cria uma entidade só de dado (<code>Type = "Generic"</code>, <code>Instance = nil</code>) que leva dano, guarda stats próprios do jogo (Custo, Ataque) e pode receber status, como qualquer entidade. Componentes que precisam de corpo (Character, Movement, Weapon, Animation) não funcionam nela. Veja ${L("receitas.cardgame")}.`,
  });

  X("api.DataManager.Get", [
    {
      t: "a partir do ID que veio no input",
      code: `
onStart = function(self, ctx)
    local alvo = ctx.input.Target and DataManager.Get(ctx.input.Target)
    if not alvo then return self:Fizzle() end
    self:Damage(alvo, 25)
end,
`,
      desc: `O código acima, dentro de uma skill, busca a entidade cujo ID o cliente mandou no payload do input e causa dano nela. O ID é a forma mais rápida de busca (um acesso de tabela). Sem alvo válido, a skill desiste com <code>Fizzle</code>, que devolve o cooldown.`,
    },
    {
      t: "a partir do Player",
      code: `
local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
    player.Chatted:Connect(function(msg)
        if msg ~= ";curar" then return end
        local entity = DataManager.Get(player)
        if entity then
            entity.Heal(entity.GetMaxHP())
        end
    end)
end)
`,
      desc: `O código acima cria um comando de chat que cura o player por completo. <code>DataManager.Get</code> aceita o próprio Player (ou o Model do personagem) porque o ID fica no atributo <code>EntityID</code> dos dois. Entre a morte e o respawn o player pode estar sem entidade: o Get devolve <code>nil</code> com um warn, e o <code>if</code> cobre isso.`,
    },
  ]);

  X("api.DataManager.Exists", {
    code: `
local MarcarAlvo = game.ReplicatedStorage.RemoteEvents.MarcarAlvo  -- RemoteEvent do jogo

MarcarAlvo.OnServerEvent:Connect(function(player, alvoID)
    if not DataManager.Exists(alvoID) then return end   -- lixo da rede: sai calado
    local alvo = DataManager.Get(alvoID)
    alvo.ApplyStatus(marcaDoCacador, { Duration = 5 })
end)
`,
    desc: `O código acima valida um ID que chegou de um cliente antes de usá-lo. <code>Exists</code> aceita qualquer valor (número, tabela, nil) e só devolve <code>true</code> para o ID de uma entidade registrada, sem escrever nada no Output: um cliente mandando lixo não enche o log de warns, como aconteceria com <code>Get</code>.`,
  });

  X("api.DataManager.GetEntityFromInstance", {
    code: `
-- uma torre atira um raio na direção para onde está virada
local params = RaycastParams.new()
params.FilterDescendantsInstances = { torre.Instance }

local origem = torre.GetCFrame()
local resultado = workspace:Raycast(origem.Position, origem.LookVector * 80, params)
if resultado then
    local atingido = DataManager.GetEntityFromInstance(resultado.Instance)
    if atingido then
        atingido.TakeDamage(10)
    end
end
`,
    desc: `O código acima transforma a peça atingida por um raycast na entidade dona dela. O raio quase sempre acerta uma parte do corpo (um braço, um acessório), não o Model; a função sobe a hierarquia até achar um Model com <code>EntityID</code>. Peça que não pertence a nenhuma entidade (chão, parede) devolve <code>nil</code>.`,
  });

  X("api.DataManager.Remove", {
    code: `
local lobo = MinionFactory.Spawn("Lobo", self.Entity.GetCFrame() * CFrame.new(0, 0, -5), self.Entity)

task.delay(15, function()
    if lobo and lobo.Active then
        local corpo = lobo.Instance
        DataManager.Remove(lobo)
        if corpo then corpo:Destroy() end
    end
end)
`,
    desc: `O código acima invoca um lobo que some depois de 15 segundos. <code>Remove</code> destrói a entidade (componentes, skills, status, inscrições) e a tira do registro, mas <b>não</b> apaga o Model do workspace: o corpo é do jogo, e quem o criou o destrói. O <code>lobo.Active</code> evita remover uma entidade que já saiu antes (morreu e foi limpa por outro script, por exemplo).`,
  });

  // ================================================================ EntityCore
  X("api.EntityCore.Listen", [
    {
      t: "espinhos (reflete parte do dano)",
      code: `
alvo:Listen({
    Role = Enum.Roles.IN,
    Breakpoint = Enum.Breakpoints.PostDamage,
    Query = { None = { Enum.Traits.DOT } },
    Owner = StateTable.OwnerToken(alvo, "Espinhos"),
    Action = function(ctx)
        local agressor = ctx.ownerEntity
        if agressor and agressor ~= alvo then
            agressor.TakeDamage(ctx.actualDamage * 0.2)
        end
    end,
})
`,
      desc: `O código acima faz a entidade <code>alvo</code> devolver 20% de todo dano que recebe para quem causou. <code>PostDamage</code> roda depois de o HP mudar, então <code>ctx.actualDamage</code> já é o dano real. A <code>Query</code> ignora dano periódico, e o <code>Owner</code> permite desligar os espinhos depois com <code>alvo:UnsubscribeByOwner(StateTable.OwnerToken(alvo, "Espinhos"))</code>.`,
    },
    {
      t: "pele de pedra (limite e expiração)",
      code: `
alvo:Listen({
    Role = Enum.Roles.IN,
    Breakpoint = Enum.Breakpoints.PreDamage,
    Query = { None = { Enum.Traits.DOT, Enum.Traits.TrueDamage } },
    TTD = 10,                                   -- some em 10 s
    Limit = { Max = 3, OnExhaust = "Remove" },  -- ou depois de 3 golpes
    Action = function(ctx)
        ctx.damage *= 0.5
    end,
})
`,
      desc: `O código acima reduz à metade os próximos 3 golpes que <code>alvo</code> receber, durante no máximo 10 segundos. Em <code>PreDamage</code> o HP ainda não mudou, então mexer em <code>ctx.damage</code> muda o dano que vai entrar (e <code>ctx.cancelled = true</code> o cancelaria). O que acabar primeiro, o tempo ou os 3 golpes, desinscreve a reação sozinho.`,
    },
  ]);

  X("api.EntityCore.ListenWorld", [
    {
      t: "fúria do chefe",
      code: `
local EntityCore = require(game.ServerScriptService.EntityData.EntityCore)

EntityCore.ListenWorld({
    Role = Enum.Roles.IN, Breakpoint = Enum.Breakpoints.OnDeath,
    Owner = StateTable.OwnerToken(chefe, "Furia"),
    Action = function(ctx, morto)
        if morto:HasComponent(Component.Affiliation) and morto.GetTeam() == "Lacaios" then
            chefe.AddModifier("DamageMult", "Furia_" .. morto.ID, "AddPercent", 0.05)
        end
    end,
})
`,
      desc: `O código acima dá ao chefe 5% a mais de dano a cada lacaio que morre, sem precisar inscrever nada em cada lacaio (nem nos que ainda vão nascer). A Action de um listener global recebe, depois do <code>ctx</code>, a entidade que emitiu o evento: aqui, quem morreu.`,
    },
    {
      t: "kill feed",
      code: `
local KillFeed = game.ReplicatedStorage.RemoteEvents.KillFeed   -- RemoteEvent do jogo

EntityCore.ListenWorld({
    Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.OnDeath,
    Action = function(ctx, matador)
        local vitima = ctx.targetEntity
        if matador:IsPlayer() and vitima then
            KillFeed:FireAllClients(matador.Player.Name, vitima.ID)
        end
    end,
})
`,
      desc: `O código acima anuncia a todos os clientes cada abate feito por um player. No canal <span class="badge out">OUT</span> o <code>OnDeath</code> é emitido no dono de quem matou (numa morte por veneno, em quem aplicou o veneno), então a entidade que chega na Action é o matador e a vítima está em <code>ctx.targetEntity</code>.`,
    },
  ]);

  X("api.EntityCore.UnsubscribeWorldByOwner", {
    code: `
local PARTIDA = {}   -- qualquer tabela serve de dono

local function comecarPartida()
    EntityCore.ListenWorld({
        Role = Enum.Roles.IN, Breakpoint = Enum.Breakpoints.OnDeath,
        Owner = PARTIDA,
        Action = function(ctx, morto) placar[morto.ID] = (placar[morto.ID] or 0) + 1 end,
    })
end

local function terminarPartida()
    EntityCore.UnsubscribeWorldByOwner(PARTIDA)
end
`,
    desc: `O código acima liga a contagem de mortes no começo da partida e a desliga no fim. Todas as inscrições globais com o mesmo <code>Owner</code> saem de uma vez, sem precisar guardar a função <code>unsubscribe</code> de cada uma.`,
  });

  X("api.EntityCore.Emit", {
    code: `
-- a mesa do card game é uma entidade só de dado que serve de "barramento" da partida
local mesa = DataManager.CreateData({})

-- uma carta com "no início do turno, compre 1"
mesa:Listen({
    Role = Enum.Roles.OUT, Breakpoint = "OnTurnStart",
    Action = function(ctx, turno)
        if ctx.jogador == donoDaCarta then comprarCarta(donoDaCarta) end
    end,
})

-- no loop da partida
mesa:Emit(Enum.Roles.OUT, "OnTurnStart", { jogador = "Azul" }, 3)
`,
    desc: `O código acima cria um breakpoint próprio do jogo, <code>OnTurnStart</code>, e o dispara a cada turno. O breakpoint é só uma string: o motor não precisa conhecê-lo. Os argumentos depois do contexto (aqui, o número do turno) chegam na Action depois do <code>ctx</code>; se o contexto não tiver <code>traits</code>, o Emit cria uma lista vazia, para as Querys funcionarem.`,
  });

  X("api.EntityCore.HasListeners", {
    code: `
local function anunciarCarta(carta)
    if not mesa:HasListeners(Enum.Roles.OUT, "OnCardPlayed") then return end
    mesa:Emit(Enum.Roles.OUT, "OnCardPlayed", {
        traits = table.clone(carta.Tipos),   -- montar o contexto tem custo
        carta = carta,
    })
end
`,
    desc: `O código acima só monta o contexto do evento se alguém estiver escutando, nesta entidade ou no mundo (${L("api.EntityCore.ListenWorld", "ListenWorld")}). Para um evento raro não faz diferença; para um disparado a cada frame ou em cada carta, evita alocar tabelas que ninguém vai ler.`,
  });

  X("api.EntityCore.UnsubscribeByOwner", {
    code: `
onStart = function(self)
    local dono = StateTable.OwnerToken(self.Entity, "Combo")
    self.Entity:UnsubscribeByOwner(dono)   -- limpa o combo de um cast anterior
    self.Entity:Listen({
        Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.onHit,
        Owner = dono, TTD = 3,
        Action = function(ctx) ctx.damage += 5 end,
    })
end,
`,
    desc: `O código acima garante que só exista uma reação de combo por vez: antes de inscrever a nova, tira a que um cast anterior pode ter deixado (ela dura 3 s e sobreviveria ao fim da skill, porque foi inscrita com <code>Listen</code> na entidade, não com <code>self:Listen</code>). O token de <code>OwnerToken</code> é por entidade; um Owner em string seria o mesmo para todas as entidades.`,
  });

  X("api.EntityCore.AddComponent", {
    code: `
-- um boneco de treino que "acorda" quando o player chega perto
if not boneco:HasComponent(Component.AI) then
    boneco:AddComponent(Component.AI, { Brain = brainDePatrulha }, true)
end
`,
    desc: `O código acima dá um cérebro a uma entidade que nasceu sem IA. O terceiro argumento <code>true</code> roda o <code>OnAdded</code> do componente na hora (é o que registra o Brain no agendador); sem ele, o componente seria criado mas nunca ligado, porque a entidade já passou da fase de carga. Adicionar um componente que a entidade já tem só gera um warn e devolve o existente.`,
  });

  X("api.EntityCore.RemoveComponent", {
    code: `
-- controle mental acabou: o NPC volta a ser um boneco parado
npc:RemoveComponent(Component.AI)

print(npc:HasComponent(Component.AI))   -- false
npc.SetBrain(outroBrain)                -- warn: componente ausente (stub)
`,
    desc: `O código acima tira a IA do NPC. O componente é destruído e as funções que ele expunha saem da entidade junto: chamá-las de novo cai no stub, que avisa uma vez no Output e devolve <code>nil</code>, em vez de mexer num componente destruído.`,
  });

  X("api.EntityCore.GetComponent", {
    code: `
onStart = function(self)
    local arma = self.Entity:GetComponent(Component.Weapon)
    if not arma then return self:Fizzle() end
    local proximo = arma:GetCurrentMode() == "Dual" and "Merged" or "Dual"
    print("trocando para", proximo, arma:GetWeaponData().Modes[proximo])
end,
`,
    desc: `O código acima pega a instância do componente de arma para ler o modo atual e o WeaponData. Na instância os métodos usam dois-pontos (<code>arma:GetCurrentMode()</code>); na entidade, a API exposta usa ponto (<code>self.Entity.GetCurrentMode()</code>). Use o componente quando precisar de algo que não está na API exposta.`,
  });

  X("api.EntityCore.HasComponent", {
    code: `
onHit = function(self, hit)
    self:Damage(hit.target, 10, { Hit = hit })
    if hit.target:HasComponent(Component.Movement) then
        hit.target.AddForce({
            Type = "Knockback", Duration = 0.2, Speed = 50, Hard = true, RequiresControl = false,
            Direction = (hit.target.GetPosition() - self.Entity.GetPosition()).Unit,
        })
    end
end,
`,
    desc: `O código acima só empurra o alvo se ele puder ser empurrado. Uma torre ou uma carta não tem Movement: sem o <code>HasComponent</code>, o <code>AddForce</code> cairia no stub (warn e nada acontece). Confira sempre que um componente for opcional para a sua mecânica.`,
  });

  X("api.EntityCore.Destroy", {
    code: `
-- prefira o DataManager.Remove; Destroy direto só se você mantém um registro próprio
local entity = DataManager.Get(id)
entity:Destroy()
print(entity.Active)               -- false
print(DataManager.Exists(id))      -- true: ainda está no registro
`,
    desc: `O código acima mostra a diferença entre <code>Destroy</code> e <code>DataManager.Remove</code>: o Destroy encerra os componentes e marca <code>Active = false</code>, mas a entidade continua registrada no DataManager. O Remove faz as duas coisas, e é o que o jogo deve usar.`,
  });

  X("api.EntityCore.IsPlayer", {
    code: `
EntityCore.ListenWorld({
    Role = Enum.Roles.IN, Breakpoint = Enum.Breakpoints.OnDeath,
    Action = function(ctx, morto)
        if morto:IsPlayer() then
            mostrarTelaDeMorte(morto.Player)
        end
    end,
})
`,
    desc: `O código acima reage só à morte de players. <code>IsPlayer</code> olha o tipo da entidade (<code>Type = "Player"</code>), e o Player fica em <code>morto.Player</code>. Um NPC possuído por um player continua sendo NPC: quem o dirige está no ${L("api.Control.GetController", "GetController")}.`,
  });

  X("api.EntityCore.IsNPC", {
    code: `
local function contarInimigosVivos()
    local n = 0
    for _, model in workspace.Inimigos:GetChildren() do
        local e = DataManager.GetEntityFromInstance(model)
        if e and e:IsNPC() and e.IsAlive() then n += 1 end
    end
    return n
end
`,
    desc: `O código acima conta os inimigos vivos numa pasta do workspace. <code>IsNPC</code> é verdadeiro para qualquer entidade com corpo que não é de player (NPC, torre, objeto); uma entidade só de dado tem <code>Type = "Generic"</code> e devolve <code>false</code>.`,
  });

  X("api.EntityCore.GetAge", {
    code: `
-- armadilha que só arma depois de 1 s (não pega quem a colocou)
zona:OnEnter(function(e)
    if armadilha:GetAge() < 1 then return end
    e.ApplyStatus(StateTable.States.Root, { Duration = 2 })
end)
`,
    desc: `O código acima ignora quem entra na zona durante o primeiro segundo de vida da armadilha. <code>GetAge</code> conta os segundos desde a criação da entidade (o Create), não desde o spawn do Model.`,
  });

  X("api.EntityCore.PrintComponents", {
    code: `
local e = DataManager.Get(player)
e:PrintComponents()
--[[ Output:
=== EntityCore: Player_123456 ===
Type: Player
Active: true
Components:
  - Health
  - Combat
  ...
]]
`,
    desc: `O código acima imprime no Output o resumo de uma entidade: ID, tipo, se está ativa e os componentes que ela tem. Serve para conferir rapidamente, na barra de comandos do Studio, por que uma função caiu no stub.`,
  });

  X("api.EntityCore.GetRegisteredComponents", {
    code: `
local EntityCore = require(game.ServerScriptService.EntityData.EntityCore)

local nomes = EntityCore.GetRegisteredComponents()
table.sort(nomes)
print(table.concat(nomes, ", "))
-- AI, Affiliation, Animation, Attributes, Character, Combat, Control, Health, Movement, Status, Weapon
`,
    desc: `O código acima lista os componentes que o motor registrou ao carregar. Um componente novo (um ModuleScript <code>XComponent</code> em <code>EntityData/Components</code>) aparece aqui como <code>X</code>; se não aparecer, o módulo deu erro ao carregar.`,
  });
})();

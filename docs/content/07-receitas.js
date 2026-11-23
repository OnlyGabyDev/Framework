/*
  Receitas: casos reais resolvidos só com a API pública, no formato de post de tutorial do fórum do
  GameMaker: uma ficha (versão, nível, onde roda, arquivos, links), o resumo (o lead da página) e o
  tutorial em passos numerados com o código completo, seguido de "Como funciona" e "Variações".

  R(id, { title, kw, resumo, nivel, lado, arquivos, links: [ids], passos: [[título, html]], funciona?, variacoes? })
*/
(function () {
  function R(id, o) {
    var ficha = '<dl class="tut-head">' +
      "<dt>Versão</dt><dd>Framework de 23/11/2026</dd>" +
      "<dt>Nível</dt><dd>" + o.nivel + "</dd>" +
      "<dt>Roda em</dt><dd>" + o.lado + "</dd>" +
      "<dt>Arquivos</dt><dd>" + o.arquivos + "</dd>" +
      "<dt>Veja também</dt><dd>" + o.links.map(function (l) { return L(l); }).join(", ") + "</dd>" +
      "</dl>";
    var passos = o.passos.map(function (p, i) { return "<h3>" + (i + 1) + ". " + p[0] + "</h3>" + p[1]; }).join("");
    DOCS.page({
      id: "receitas." + id, parent: "receitas", title: o.title, kw: o.kw, lead: o.resumo,
      html: ficha + "<h2>Tutorial</h2>" + passos +
        (o.funciona ? "<h2>Como funciona</h2>" + o.funciona : "") +
        (o.variacoes ? "<h2>Variações</h2>" + o.variacoes : ""),
    });
  }

  // requires que se repetem nos módulos de skill
  var REQ = `
local StateTable = require(game.ServerStorage.Modules.Combat.StateTable)
local Component = require(game.ServerScriptService.EntityData.ComponentsExport)
local DataManager = require(game.ServerScriptService.EntityData.DataManager)
local Enum = StateTable.Enum`;

  DOCS.page({
    id: "receitas", title: "Receitas", kw: "receitas exemplos como fazer tutorial cookbook passo a passo",
    lead: "Mecânicas comuns resolvidas só com a API pública, sem mexer no motor. Cada receita é um tutorial completo: o que você vai construir, os arquivos, o código passo a passo e como ele funciona.",
    html: `
<p>As receitas seguem o formato dos tutoriais do fórum do GameMaker: uma ficha no topo (nível, onde o código roda, quais arquivos você cria), o resumo e o tutorial em passos. O código de cada passo é completo; os requires que se repetem aparecem no começo do módulo.</p>
${T(["Nível", "Para quem"], [
  ["Iniciante", "Primeira skill, primeiro status. Só precisa do " + L("basico", "Guia básico") + " até Eventos."],
  ["Intermediário", "Combina dois ou três sistemas (status + eventos, zona + forças, input + skill)."],
  ["Avançado", "Usa possessão, herança, cadeias ou monta um sistema de jogo inteiro em cima do framework."],
])}
${N("<p>Para a página de uma função específica, com exemplos curtos de cada uma, use a " + L("api", "Referência da API") + ".</p>")}`,
  });

  // ================================================================ Iniciante
  R("skill", {
    title: "Sua primeira skill", nivel: "Iniciante", lado: "Servidor",
    kw: "primeira skill criar skill golpe melee tutorial soco",
    resumo: "Um soco com a hitbox da arma, dano e um Stun curto, equipado no slot Ability2 (tecla 2).",
    arquivos: "<code>ServerStorage/DataBase/SkillDatabase/Schema/Soco.luau</code> (novo) e onde você equipa.",
    links: ["conceitos.skills", "api.skill.data", "api.skill.Damage", "api.Combat.EquipSkill"],
    passos: [
      ["Crie o módulo da skill", `<p>Um ModuleScript dentro da pasta do kit no SkillDatabase. O nome do arquivo vira a chave (<code>Schema_Soco</code>) e a pasta vira o kit dono (de onde a skill tira animações).</p>` + C(REQ + `

return {
    data = {
        cooldown = 1.5,
        duration = 0.4,
        traits = { Enum.Traits.Melee },
        requires = { Component.Weapon },   -- sem arma, o motor recusa o cast
        damage = 10,                       -- campo livre: o motor não lê
    },
    callbacks = {
        onStart = function(self)
            self.Entity.SetActionState(self.statusTable.ActionStates.Out.cast, self.Runner)
            self:StartHitbox(self.data.duration)
        end,
        onHit = function(self, hit)
            local ok = self:Damage(hit.target, self.data.damage, { Hit = hit })
            if ok then
                self:ApplyStatus(self.statusTable.States.Stun, { Target = hit.target, Duration = 0.3 })
            end
        end,
    },
}
`)],
      ["Equipe no slot", `<p>Para testar, equipe por código (num Script de teste, ou pela barra de comandos do Studio com o jogo rodando):</p>` + C(`
local DataManager = require(game.ServerScriptService.EntityData.DataManager)
local Keys = require(game.ServerStorage.DataBase.SkillDatabase).Keys
local Intents = require(game.ReplicatedStorage.Input.Intents)

local player = game.Players:GetPlayers()[1]
DataManager.Get(player).EquipSkill(Intents.Id.Ability2, Keys.Schema.Soco)
`) + `<p>Para ficar no personagem de vez, ponha <code>[Intents.Ability2] = Keys.Schema.Soco</code> no <code>Loadout</code> da forma em <code>CharacterDatabase/Schema/Base.luau</code>.</p>`],
      ["Teste no Play", `<p>Aperte 2 perto do boneco de treino. O soco dura 0,4 s, acerta cada alvo uma vez e atordoa por 0,3 s; o próximo soco só sai depois de 1,5 s.</p>`],
    ],
    funciona: `<ul>
<li><code>onStart</code> trava a ação com o ActionState <b>Out</b> (o próprio Dash não cancela o soco) e liga a hitbox da arma só para esta ativação.</li>
<li>Cada alvo tocado chega uma vez no <code>onHit</code>. <code>self:Damage</code> passa pelo lado do atacante (DamageMult, <code>OUT.onHit</code>) e do alvo (iFrame, bloqueio, Defense).</li>
<li>O Stun só entra se o dano entrou de fato (<code>ok</code>): um golpe absorvido pelo iFrame não atordoa.</li>
<li>Nada a limpar: ActionState e hitbox saem sozinhos no fim do runner.</li>
</ul>`,
    variacoes: `<ul>
<li>Animação: <code>self.Entity.PlayAnimation(self.charLib.M1.M1Start)</code> no <code>onStart</code> e ligue a hitbox num marcador com ${L("api.Animation.OnMarker", "OnMarker")}.</li>
<li>Combo de dois golpes: um <code>onRecast</code> com <code>self.counter</code>, como no M1 da Schema (declare <code>cooldownPolicy = { recast = ... }</code>).</li>
<li>Knockback: some um ${L("api.Movement.AddForce", "AddForce")} no <code>onHit</code>.</li>
</ul>`,
  });

  R("dot", {
    title: "Veneno (DoT com stacks)", nivel: "Iniciante", lado: "Servidor",
    kw: "dot veneno poison sangramento bleed queimadura stack dano periódico",
    resumo: "Um status de dano periódico que acumula até 5 stacks, aplicado em todo acerto de uma skill, com o crédito do abate para quem envenenou.",
    arquivos: "<code>ServerStorage/Modules/Combat/StateTable/Status/Debuffs/Poison.luau</code> (novo) e a skill que aplica.",
    links: ["conceitos.status", "api.skill.statusdata", "api.Status.GetStatusCounter", "api.StateTable.EffectOwner"],
    passos: [
      ["Crie o status", `<p>Status ficam em <code>StateTable/Status/Buffs</code> ou <code>Debuffs</code> e são acessados pelo nome do módulo: <code>StateTable.Status.Poison</code>.</p>` + C(`
-- StateTable/Status/Debuffs/Poison.luau
local Enum = require(script.Parent.Parent.Parent.Enum)

return {
    data = {
        name = "Poison",
        category = Enum.Categories.Debuff,
        duration = 5,
        tickRate = 0.5,     -- campos livres: o status lê em self.data
        damage = 3,
        traits = { Enum.Traits.DOT, Enum.Traits.Stackable },
        stackOnSelf = true, -- reaplicar soma 1 em self.counter na mesma instância
        maxStacks = 5,
    },
    callbacks = {
        onStart = function(self) self.t = 0 end,
        onStep = function(self, dt)
            self.t += dt
            if self.t >= self.data.tickRate then
                self.t = 0
                self.Entity.TakeDamage(self.data.damage * self.counter, self.Runner)
            end
        end,
    },
}
`)],
      ["Aplique em todo acerto da skill", `<p>Declare o status em <code>data.effects</code> da skill: cada golpe que acertar aplica (ou empilha) o veneno, sem código no <code>onHit</code>.</p>` + C(`
data = {
    cooldown = 1, duration = 0.4,
    effects = { StateTable.Status.Poison },
},
callbacks = {
    onStart = function(self) self:StartHitbox(self.data.duration) end,
    onHit = function(self, hit) self:Damage(hit.target, 5, { Hit = hit }) end,
},
`)],
      ["Um antídoto (opcional)", C(`
-- item ou skill de cura: tira 2 stacks, ou o veneno inteiro
alvo.RemoveAmount("Poison", 2)
alvo.RemoveStatus("Poison")
`)],
    ],
    funciona: `<ul>
<li>O status é um runner como a skill: <code>onStep</code> roda a cada frame e conta o próprio tique.</li>
<li><code>self.Runner</code> como fonte do dano dá ao contexto a trait DOT (escudos de DoT e listeners filtram por ela) e credita a morte a quem aplicou o veneno, não à vítima onde ele roda.</li>
<li>Com <code>stackOnSelf</code>, reaplicar soma 1 em <code>self.counter</code>, zera o tempo e mantém o crédito de quem aplicou o 1º stack. No 5º stack, reaplicar só renova a duração (<code>refreshOnMax</code>).</li>
<li>Por padrão, um golpe totalmente bloqueado não aplica o veneno (<code>Enum.EffectDefaults.onBlocked = false</code>); declare <code>effectPolicy</code> na skill para mudar.</li>
</ul>`,
    variacoes: `<ul>
<li>Só no golpe final: em vez de <code>data.effects</code>, passe <code>Effects = { StateTable.Status.Poison }</code> no ${L("api.skill.Damage", "self:Damage")} daquele golpe.</li>
<li>Ícone na HUD: ${L("receitas.buff")}.</li>
<li>Imunidade a DoT: o status <code>StatusShield</code> de exemplo barra status com a trait DOT.</li>
</ul>`,
  });

  R("lifesteal", {
    title: "Roubo de vida", nivel: "Iniciante", lado: "Servidor",
    kw: "lifesteal roubo de vida vampirismo curar ao bater",
    resumo: "Cura quem bate em 20% do dano direto causado, como passiva permanente ou como buff com duração.",
    arquivos: "Um Script do jogo (passiva) ou <code>StateTable/Status/Buffs/Vampirismo.luau</code> (buff).",
    links: ["conceitos.eventos", "api.EntityCore.Listen", "api.Health.Heal"],
    passos: [
      ["Passiva: escute o dano que a entidade causa", C(`
entity:Listen({
    Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.OnDamage,
    Query = { None = { Enum.Traits.DOT } },
    Owner = StateTable.OwnerToken(entity, "Lifesteal"),
    Action = function(ctx)
        entity.Heal((ctx.actualDamage or 0) * 0.2)
    end,
})
`)],
      ["Buff: o mesmo, mas como status com duração", C(`
-- StateTable/Status/Buffs/Vampirismo.luau
local Enum = require(script.Parent.Parent.Parent.Enum)
return {
    data = { name = "Vampirismo", category = Enum.Categories.Buff, duration = 8 },
    callbacks = {
        onStart = function(self)
            self:Listen({
                Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.OnDamage,
                Query = { None = { Enum.Traits.DOT } },
                Action = function(ctx) self.Entity.Heal((ctx.actualDamage or 0) * 0.2) end,
            })
        end,
    },
}
`) + `<p>Aplique com <code>self:ApplyStatus(StateTable.Status.Vampirismo)</code> numa skill.</p>`],
    ],
    funciona: `<ul>
<li><span class="badge out">OUT</span> <code>OnDamage</code> chega no dono do dano depois que o HP do alvo mudou; <code>ctx.actualDamage</code> é o que saiu de fato (um alvo com 5 de vida devolve no máximo 5).</li>
<li>A Query tira o dano periódico (senão um veneno curaria o tempo todo).</li>
<li>No buff, <code>self:Listen</code> inscreve no portador com o runner como dono: a reação some quando o buff acaba.</li>
</ul>`,
  });

  R("sobrevida", {
    title: "Sobrevida (overheal)", nivel: "Iniciante", lado: "Servidor",
    kw: "sobrevida overheal escudo de vida hp acima do máximo decair",
    resumo: "Cura que passa do máximo e uma sobrevida que decai devagar até o MaxHP.",
    arquivos: "<code>StateTable/Status/Buffs/SobrevidaDecai.luau</code> (novo) e onde você cura.",
    links: ["conceitos.cura", "api.Health.Heal", "api.Health.SetHP"],
    passos: [
      ["Cure acima do máximo", C(`
alvo.Heal(50, { Cap = 1.5 })          -- até 150% do MaxHP
alvo.SetHP(alvo.GetMaxHP() + 30)      -- ou um valor exato, sem corte
`)],
      ["Faça o excedente decair", C(`
-- StateTable/Status/Buffs/SobrevidaDecai.luau: sem duração, dura até ser removido
local Enum = require(script.Parent.Parent.Parent.Enum)
return {
    data = { name = "SobrevidaDecai", category = Enum.Categories.Internal, porSegundo = 5 },
    callbacks = {
        onStep = function(self, dt)
            local hp, max = self.Entity.GetHP(), self.Entity.GetMaxHP()
            if hp > max then
                self.Entity.SetHP(math.max(max, hp - self.data.porSegundo * dt))
            end
        end,
    },
}
`) + `<p>Aplique uma vez, quando a entidade nasce: <code>entity.ApplyStatus(StateTable.Status.SobrevidaDecai, {})</code>.</p>`],
    ],
    funciona: `<ul>
<li>HP acima do MaxHP é design do framework. A cura tem teto (<code>HealCap</code> do config ou <code>Cap</code> da cura) e nunca reduz o HP; <code>SetHP</code> não tem teto.</li>
<li>O status sem duração roda <code>onStep</code> para sempre e só age quando há excedente. Baixar o HP pelo <code>SetHP</code> não é dano: não passa por bloqueio nem emite eventos de dano.</li>
</ul>`,
  });

  R("buff", {
    title: "Buff de stat com ícone", nivel: "Iniciante", lado: "Servidor e cliente",
    kw: "buff stat ícone icone hud fúria velocidade dano modificador interface",
    resumo: "Um buff de 6 s com +30% de dano e +4 de velocidade, e o ícone dele na tela do player com o tempo restante.",
    arquivos: "<code>StateTable/Status/Buffs/Furia.luau</code>, um Script do servidor (ícones) e um LocalScript (HUD).",
    links: ["conceitos.stats", "conceitos.hud", "api.Attributes.AddModifier"],
    passos: [
      ["Crie o status", C(`
-- StateTable/Status/Buffs/Furia.luau
local Enum = require(script.Parent.Parent.Parent.Enum)
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
`) + `<p>Numa skill: <code>self:ApplyStatus(StateTable.Status.Furia)</code>.</p>`],
      ["Mande os ícones ao cliente (servidor)", `<p>Todo status emite <span class="badge out">OUT</span> <code>onStart</code> e <code>onEnd</code> no portador. Um listener global pega os de todos os players:</p>` + C(`
-- ServerScriptService/StatusIcons.server.luau
local EntityCore = require(game.ServerScriptService.EntityData.EntityCore)
local StateTable = require(game.ServerStorage.Modules.Combat.StateTable)
local Enum = StateTable.Enum

local remote = Instance.new("RemoteEvent")
remote.Name = "StatusIcons"
remote.Parent = game.ReplicatedStorage.RemoteEvents

local function enviar(ctx, entity, ligado)
    local r = ctx.sourceRunner
    if entity.Player and r and r.type == Enum.Types.Status
        and r.data.category ~= Enum.Categories.Internal then   -- marcadores internos não têm ícone
        remote:FireClient(entity.Player, r.skillName, ligado, ligado and r:GetRemainingTime() or 0)
    end
end
EntityCore.ListenWorld({ Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.onStart,
    Action = function(ctx, entity) enviar(ctx, entity, true) end })
EntityCore.ListenWorld({ Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.onEnd,
    Action = function(ctx, entity) enviar(ctx, entity, false) end })
`)],
      ["Desenhe o ícone (cliente)", C(`
-- StarterPlayerScripts/StatusHUD.client.luau (supõe uma ScreenGui "HUD" com um Frame "Status" e um UIListLayout)
local remote = game.ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("StatusIcons")
local lista = game.Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("HUD"):WaitForChild("Status")

remote.OnClientEvent:Connect(function(nome, ligado, restante)
    local icone = lista:FindFirstChild(nome)
    if not ligado then
        if icone then icone:Destroy() end
        return
    end
    icone = icone or Instance.new("TextLabel")
    icone.Name, icone.Size, icone.Parent = nome, UDim2.fromOffset(48, 48), lista
    local fim = os.clock() + (restante or 0)
    task.spawn(function()
        while icone.Parent do
            icone.Text = nome .. "\\n" .. string.format("%.1f", math.max(0, fim - os.clock()))
            task.wait(0.1)
        end
    end)
end)
`)],
    ],
    funciona: `<ul>
<li>O ID da aplicação (<code>self.ID</code>) é a origem dos modificadores: duas Fúrias de fontes diferentes têm modificadores separados, e o <code>onEnd</code> de uma não tira o da outra.</li>
<li>O <code>onEnd</code> roda em qualquer fim (duração, purificação, morte), então o stat sempre volta.</li>
<li>A HUD só mostra: quem decide é o servidor. Os nomes dos ícones são os <code>data.name</code> dos status, e qualquer status novo aparece sem mudar a HUD.</li>
</ul>`,
  });

  R("hold", {
    title: "Skill carregada (hold)", nivel: "Iniciante", lado: "Servidor",
    kw: "carregar charge hold segurar soltar onrelease heldtime",
    resumo: "Segurar para carregar e soltar para disparar um corte proporcional à carga; um toque curto dá um golpe rápido.",
    arquivos: "<code>SkillDatabase/Schema/Carregado.luau</code> (novo).",
    links: ["conceitos.input", "api.GestureResolver.Release", "api.HitboxPresets.ExpandingCone"],
    passos: [
      ["Declare os gestos e o callback de soltar", C(REQ + `
local Intents = require(game.ReplicatedStorage.Input.Intents)
local Presets = require(game.ServerStorage.Modules.Combat.Hitbox.HitboxPresets)

local function corte(self, tamanho, dano)
    local atingidos = {}
    local hitbox = Presets.ExpandingCone(self.Entity, self.Entity.GetCFrame() * CFrame.new(0, 0, -3),
        "X", 40, tamanho, 0.25)
    hitbox:OnHit(function(result)
        local e = DataManager.GetEntityFromInstance(result.Instance)
        if e and not atingidos[e] and StateTable.CanAffect(self, e) then
            atingidos[e] = true
            self:Damage(e, dano)
        end
    end)
end

return {
    data = { cooldown = 3, duration = 5, input = { Hold = 0.25, Tap = true }, damage = 40 },
    callbacks = {
        onStart = function(self, ctx)
            local gesto = ctx.input and ctx.input.Gesture
            if gesto ~= Intents.Gesture.Hold then
                corte(self, 6, 10)                 -- toque curto: golpe rápido
                return self:Stop(false)
            end
            self.travaID = self.Entity.ApplyStatus(StateTable.States.Root, { Source = self.Runner })
        end,
        onRelease = function(self, ctx)
            local carga = math.clamp(ctx.input.HeldTime / 2, 0.2, 1)   -- 2 s = carga cheia
            corte(self, 6 + 10 * carga, self.data.damage * carga)
            task.delay(0.25, function() self:Stop(false) end)          -- vive até o corte acabar
        end,
        onEnd = function(self)
            if self.travaID then self.Entity.RemoveStatusByID(self.travaID) end
        end,
    },
}
`)],
    ],
    funciona: `<ul>
<li>Com <code>input = { Hold = 0.25, Tap = true }</code>, o botão vira um gesto: soltar antes de 0,25 s ativa a skill com <code>Gesture = "Tap"</code> (sem Release depois); segurar ativa com <code>"Hold"</code> aos 0,25 s, e o Release chega no <code>onRelease</code> da mesma ativação com <code>HeldTime</code>.</li>
<li>O Root sem duração prende o player enquanto carrega; o <code>onEnd</code> o tira em qualquer fim (soltou, levou Stun, morreu, ou passou dos 5 s da duração).</li>
<li>O corte é uma hitbox solta: o <code>atingidos</code> evita contar várias peças do mesmo corpo.</li>
</ul>`,
  });

  // ================================================================ Intermediário
  R("projetil", {
    title: "Projétil teleguiado", nivel: "Intermediário", lado: "Servidor (e o provider de alvo no cliente)",
    kw: "projétil projectile homing teleguiado bola de fogo tiro magia",
    resumo: "Uma bola de energia que persegue a entidade clicada, com filtro de time e um acerto por alvo.",
    arquivos: "<code>SkillDatabase/Schema/Orbe.luau</code> (novo) e o provider de mira do cliente.",
    links: ["receitas.mira", "api.HitboxPresets.HomingBolt", "api.StateTable.CanAffect"],
    passos: [
      ["Mande o alvo junto do input (cliente)", `<p>O servidor precisa saber em quem o player clicou. Siga o passo 1 de ${L("receitas.mira")}.</p>`],
      ["Crie a skill", C(REQ + `
local Presets = require(game.ServerStorage.Modules.Combat.Hitbox.HitboxPresets)

return {
    data = { cooldown = 4, duration = 3, damage = 20 },
    callbacks = {
        onStart = function(self, ctx)
            local alvo = ctx.input.Target and DataManager.Get(ctx.input.Target)
            if not alvo or not alvo:HasComponent(Component.Character) then
                return self:Fizzle()               -- sem alvo: devolve o cooldown
            end
            local acertados = {}
            local hitbox = Presets.HomingBolt(self.Entity, self.Entity.GetCFrame(),
                function() return alvo.GetRoot() end, 70, 2, self.data.duration)
            hitbox:OnHit(function(result)
                local e = DataManager.GetEntityFromInstance(result.Instance)
                if e and not acertados[e] and StateTable.CanAffect(self, e) then
                    acertados[e] = true
                    self:Damage(e, self.data.damage)
                    hitbox:HitStop()               -- o orbe some no primeiro acerto
                end
            end)
        end,
    },
}
`)],
    ],
    funciona: `<ul>
<li><code>HomingBolt</code> cria um Spherecast de raio 2 a 70 studs/s que mira o root do alvo a cada frame e se limpa sozinho ao parar (no acerto ou depois de 3 s).</li>
<li>O projétil pode tocar outras entidades no caminho; <code>CanAffect</code> aplica a regra de alvo da skill (por padrão, aliados passam ilesos).</li>
<li>O <code>Fizzle</code> devolve o cooldown: clicar no vazio não pune o player.</li>
</ul>`,
    variacoes: `<ul>
<li>Curva limitada (desviável): passe o 7º argumento, em rad/s.</li>
<li>Sem alvo, em linha reta: ${L("api.HitboxSpawner.Spawn", "HitboxSpawner.Spawn")} com ${L("api.HitboxBehaviors.LinearMove", "LinearMove")} na direção de <code>GetAimDirection()</code>.</li>
</ul>`,
  });

  R("mira", {
    title: "Mira com alvo e ponto", nivel: "Intermediário", lado: "Cliente e servidor",
    kw: "mira alvo ponto target point mouse chão payload clicar meteoro",
    resumo: "Mandar a entidade sob o mouse e o ponto do mundo junto com o input, e usar os dois numa skill de área no chão.",
    arquivos: "<code>StarterPlayerScripts/Mira.client.luau</code> (novo) e <code>SkillDatabase/Schema/Meteoro.luau</code> (novo).",
    links: ["conceitos.input", "api.InputService.SetPayloadProvider", "api.Intents.SanitizePayload"],
    passos: [
      ["Provider de mira (cliente)", C(`
-- StarterPlayerScripts/Mira.client.luau
local InputService = require(script.Parent:WaitForChild("InputService"))
local mouse = game.Players.LocalPlayer:GetMouse()

InputService.SetPayloadProvider(function(intent)
    local model = mouse.Target and mouse.Target:FindFirstAncestorOfClass("Model")
    return {
        Target = model and model:GetAttribute("EntityID"),
        Point = mouse.Hit.Position,
    }
end)
`)],
      ["A skill usa o ponto (servidor)", C(REQ + `
local VFXManager = require(game.ServerScriptService.Modules.VFX.VFXManager)

return {
    data = { cooldown = 8, duration = 1, alcance = 60, raio = 8, damage = 35 },
    callbacks = {
        onStart = function(self, ctx)
            local ponto = ctx.input.Point
            if not ponto or (ponto - self.Entity.GetPosition()).Magnitude > self.data.alcance then
                return self:Fizzle()               -- longe demais: devolve o cooldown
            end
            VFXManager.PlayNear(ponto, 250, "Meteoro", { Position = ponto })
            task.delay(0.8, function()
                local atingidos = {}
                for _, part in workspace:GetPartBoundsInRadius(ponto, self.data.raio) do
                    local e = DataManager.GetEntityFromInstance(part)
                    if e and not atingidos[e] and StateTable.CanAffect(self, e) then
                        atingidos[e] = true
                        self:Damage(e, self.data.damage)
                    end
                end
            end)
        end,
    },
}
`)],
    ],
    funciona: `<ul>
<li>O provider é chamado a cada Press/Release e o payload vai junto do input. O servidor só deixa passar <code>Target</code> string que é uma entidade existente e <code>Point</code> Vector3 finito dentro do mundo; o resto vira <code>nil</code>.</li>
<li>Alcance e linha de visão são regra da skill: o servidor nunca confia que o cliente mandou um ponto razoável.</li>
<li>O dano cai 0,8 s depois (o tempo do efeito), ainda dentro da duração de 1 s da skill.</li>
</ul>`,
  });

  R("parry", {
    title: "Parry", nivel: "Intermediário", lado: "Servidor",
    kw: "parry aparar contra-ataque reflexo refletir defesa janela",
    resumo: "Uma janela de 0,3 s que cancela o próximo golpe recebido e atordoa quem bateu.",
    arquivos: "<code>SkillDatabase/Schema/Parry.luau</code> (novo).",
    links: ["conceitos.eventos", "api.skill.Listen", "conceitos.cadeias"],
    passos: [
      ["Crie a skill", C(REQ + `

return {
    data = { cooldown = 2, duration = 0.3 },
    callbacks = {
        onStart = function(self)
            self:Listen({
                Role = Enum.Roles.IN, Breakpoint = Enum.Breakpoints.PreDamage,
                Query = { None = { Enum.Traits.DOT } },
                Limit = { Max = 1, OnExhaust = "Remove" },
                Action = function(ctx)
                    ctx.cancelled, ctx.reason = true, "Parry"
                    local atacante = ctx.ownerEntity
                    if atacante and atacante ~= self.Entity then
                        self:ApplyStatus(self.statusTable.States.Stun, { Target = atacante, Duration = 1 })
                    end
                end,
            })
        end,
    },
}
`)],
    ],
    funciona: `<ul>
<li><span class="badge in">IN</span> <code>PreDamage</code> roda antes do HP mudar: <code>ctx.cancelled = true</code> anula o golpe, e o <code>TakeDamage</code> de quem bateu devolve <code>false, "Parry"</code>.</li>
<li>O <code>Limit</code> faz a janela pegar um golpe só; a inscrição some no fim dos 0,3 s mesmo sem golpe (é do runner).</li>
<li>Dano periódico não é aparado (Query).</li>
<li>Refletir dano entre dois parries é uma cadeia; os ${L("conceitos.cadeias", "limites de cadeia")} cortam o ping-pong.</li>
</ul>`,
  });

  R("escudo", {
    title: "Escudo de bloqueio", nivel: "Intermediário", lado: "Servidor",
    kw: "escudo bloqueio block bloquear defender segurar guarda muralha reduzir dano",
    resumo: "Segurar o botão levanta a guarda (60% menos dano de skills, andando devagar); soltar abaixa. Golpes com BlockBreak quebram a guarda.",
    arquivos: "<code>StateTable/Status/Buffs/Guarda.luau</code> e <code>SkillDatabase/Schema/Bloquear.luau</code> (novos).",
    links: ["conceitos.dano", "enum.dano", "api.skill.TriggerAction"],
    passos: [
      ["O status de guarda", C(`
-- StateTable/Status/Buffs/Guarda.luau
local Enum = require(script.Parent.Parent.Parent.Enum)
return {
    data = {
        name = "Guarda", category = Enum.Categories.Buff,
        tags = { [Enum.Tags.block] = true },
        block = { mode = Enum.BlockModes.Percent, value = 0.6 },
        ShieldsFromType = { Enum.Types.Skill },   -- só dano de skill (não DoT de status nem ambiente)
    },
    callbacks = {
        onStart = function(self)
            self.Entity.AddModifier(Enum.Stats.Speed, self.ID, Enum.ModifierType.MultPercent, 0.5)
        end,
        onEnd = function(self)
            self.Entity.RemoveModifier(Enum.Stats.Speed, self.ID)
        end,
    },
}
`)],
      ["A skill de segurar", C(REQ + `

return {
    data = {
        cooldown = 0.5, duration = 10,
        input = { Hold = 0.1, Tap = false },                         -- só ativa segurando
        cooldownPolicy = { start = Enum.CooldownStart.End },         -- o cooldown conta ao abaixar
    },
    callbacks = {
        onStart = function(self)
            self.guardaID = self.Entity.ApplyStatus(StateTable.Status.Guarda, { Source = self.Runner })
        end,
        onRelease = function(self) self:Stop(false) end,
        onEnd = function(self)
            if self.guardaID then self.Entity.RemoveStatusByID(self.guardaID) end
        end,
    },
}
`)],
    ],
    funciona: `<ul>
<li>A tag <code>block</code> faz todo golpe passar pelo bloqueio do status dono dela; sem <code>onTrigger</code>, vale o <code>data.block</code> declarado (Percent tira 60%).</li>
<li>Um golpe com a trait <code>BlockBreak</code> encerra a guarda (a menos que ela tenha <code>Unbreakable</code>); <code>TrueHit</code> ignora o bloqueio comum (a menos que ela tenha <code>TrueBlock</code>).</li>
<li>A guarda é um status sem duração, preso à skill pelo ID: soltar, levar Stun (a tag <code>interrupt</code> cancela a skill) ou passar dos 10 s abaixam a guarda.</li>
</ul>`,
    variacoes: `<ul>
<li>Parry no começo da guarda: junte a ${L("receitas.parry")} nos primeiros 0,2 s do <code>onStart</code>.</li>
<li>Bloqueio que decide por golpe: troque o <code>block</code> por um <code>onTrigger(self, hitCtx)</code> que devolve o dano novo (ou <code>nil</code> para não bloquear).</li>
</ul>`,
  });

  R("combo", {
    title: "Combo entre skills", nivel: "Intermediário", lado: "Servidor",
    kw: "combo sequência janela combowindow encadear lançar finalizador",
    resumo: "A skill A lança o alvo e abre uma janela de 1,2 s; a skill B, dentro da janela, vira um finalizador. Nenhuma conhece a outra.",
    arquivos: "Duas skills (<code>Lancar.luau</code> e <code>Finalizar.luau</code>).",
    links: ["api.ComboWindow", "api.ComboWindow.Consume", "api.Movement.AddForce"],
    passos: [
      ["Skill A marca a janela", C(REQ + `
local ComboWindow = require(game.ServerStorage.DataBase.SkillDatabase.BaseSkills).ComboWindow

return {
    data = { cooldown = 3, duration = 0.4 },
    callbacks = {
        onStart = function(self) self:StartHitbox(self.data.duration) end,
        onHit = function(self, hit)
            self:Damage(hit.target, 10, { Hit = hit })
            hit.target.AddForce({ Type = "Lancamento", Duration = 0.3, Speed = 40,
                Direction = Vector3.yAxis, Hard = true, RequiresControl = false })
            ComboWindow.Mark(self.Entity, "Lancamento", 1.2, { alvo = hit.target }, self.Runner)
        end,
    },
}
`)],
      ["Skill B consome", C(REQ + `
local ComboWindow = require(game.ServerStorage.DataBase.SkillDatabase.BaseSkills).ComboWindow

return {
    data = { cooldown = 1, duration = 0.3 },
    callbacks = {
        onStart = function(self)
            local combo = ComboWindow.Consume(self.Entity, "Lancamento")
            if combo and combo.alvo and combo.alvo.Active then
                self:Damage(combo.alvo, 40)                         -- finalizador
            else
                self:StartHitbox(self.data.duration)                -- golpe comum
            end
        end,
        onHit = function(self, hit) self:Damage(hit.target, 8, { Hit = hit }) end,
    },
}
`)],
    ],
    funciona: `<ul>
<li>A janela é um status interno em quem casta, com o payload guardado nele. <code>Consume</code> lê e fecha; depois de 1,2 s ela fecha sozinha.</li>
<li>As duas skills só combinam o nome do marcador (<code>"Lancamento"</code>): dá para trocar a A por outra que lance, sem mexer na B.</li>
</ul>`,
  });

  R("vento", {
    title: "Zona de vento", nivel: "Intermediário", lado: "Servidor",
    kw: "vento ventilador zona empurrar corrente área força ambiente",
    resumo: "Um ventilador do mapa que empurra quem entra no corredor de ar à frente dele, e uma versão de skill (tornado em volta de quem casta).",
    arquivos: "<code>ServerScriptService/Ventilador.server.luau</code> (novo) ou uma skill.",
    links: ["conceitos.zonas", "api.AreaBehaviors.BindDirectionalForce", "api.AreaEffect.new"],
    passos: [
      ["Ventilador do mapa", C(`
-- ServerScriptService/Ventilador.server.luau
local AreaEffect = require(game.ServerStorage.Modules.Combat.AreaEffect)
local AreaBehaviors = require(game.ServerStorage.Modules.Combat.AreaBehaviors)

local ventilador = workspace.Ventilador   -- a frente dele (LookVector) é para onde o ar sopra

local zona = AreaEffect.new(function()
    return ventilador.CFrame * CFrame.new(0, 0, -15)      -- o corredor começa à frente
end, "Box", Vector3.new(10, 8, 30), 15)

AreaBehaviors.BindDirectionalForce(zona, function() return ventilador.CFrame.LookVector end, 30, "Vento")
zona:Start()
`)],
      ["Tornado de skill", C(REQ + `
local AreaEffect = require(game.ServerStorage.Modules.Combat.AreaEffect)
local AreaBehaviors = require(game.ServerStorage.Modules.Combat.AreaBehaviors)

return {
    data = { cooldown = 10, duration = 4 },
    callbacks = {
        onStart = function(self)
            local centro = function() return self.Entity.GetCFrame() end
            local zona = AreaEffect.new(centro, "Sphere", 14, 15)
            zona:SetFilter(StateTable.AffectsFilter(self))       -- aliados ficam de fora
            AreaBehaviors.BindDirectionalForce(zona, function()
                return Vector3.yAxis * 0.4 + self.Entity.GetLookDirection()
            end, 25, "Tornado")
            zona:Start()
            self:Own(function() zona:Stop() end)
        end,
    },
}
`)],
    ],
    funciona: `<ul>
<li>A zona consulta a forma 15 vezes por segundo (sem <code>.Touched</code>). A função de CFrame é relida a cada poll: girar o ventilador gira o corredor.</li>
<li><code>BindDirectionalForce</code> liga uma Force Soft (soma com a caminhada) e externa (empurra quem está em Stun) da entrada até a saída da zona. Ao sair, ela é removida: não sobra empurrão além da borda.</li>
<li>No corpo de player, a zona testa a posição prevista pelo atraso de rede, então a saída vale quando ele sai de verdade na tela dele.</li>
<li>Na skill, o <code>Own</code> para a zona no fim; quem estava dentro sai pelo OnExit e perde a Force.</li>
</ul>`,
  });

  R("agarrao", {
    title: "Agarrão e arremesso", nivel: "Intermediário", lado: "Servidor",
    kw: "agarrão grab carregar segurar attachto levar junto arremessar jogar",
    resumo: "Agarrar quem a hitbox tocar, carregar sem atraso durante a skill e arremessar para a frente no fim.",
    arquivos: "<code>SkillDatabase/Schema/Agarrar.luau</code> (novo).",
    links: ["api.Movement.AttachTo", "api.CollisionGroups.Assign", "api.skill.Own"],
    passos: [
      ["Crie a skill", C(REQ + `
local CollisionGroups = require(game.ServerScriptService.Modules.Physics.CollisionGroups)

return {
    data = { cooldown = 6, duration = 1.5, requires = { Component.Weapon } },
    callbacks = {
        onStart = function(self)
            self.presos = {}
            self:StartHitbox(0.3)                                   -- só pega no começo
        end,
        onHit = function(self, hit)
            local alvo = hit.target
            if self.presos[alvo] or not alvo:HasComponent(Component.Movement) then return end
            local release = alvo.AttachTo(self.Entity.GetRoot(), CFrame.new(0, 0, -4))
            if not release then return end
            self.presos[alvo] = true
            local restaura = CollisionGroups.Assign(alvo.Instance, CollisionGroups.Grabbed)
            self:Own(function() release(); restaura() end)        -- solta em qualquer fim
        end,
        onEnd = function(self, ctx)
            if ctx.reason ~= Enum.EndReasons.Duration then return end   -- cancelado: só solta
            local frente = self.Entity.GetLookDirection()
            for alvo in self.presos do
                if alvo.Active then
                    alvo.AddForce({ Type = "Arremesso", Duration = 0.4, Speed = 70,
                        Direction = (frente + Vector3.yAxis * 0.5).Unit,
                        Hard = true, RequiresControl = false })
                    self:Damage(alvo, 15)
                end
            end
        end,
    },
}
`)],
    ],
    funciona: `<ul>
<li><code>AttachTo</code> põe o alvo no assembly de quem agarra com um WeldConstraint: sem atraso, inclusive quando quem agarra é um player. Enquanto preso, o alvo não anda nem sofre Forces.</li>
<li>Os <code>Own</code> rodam antes do <code>onEnd</code>: no <code>onEnd</code> os alvos já estão soltos e podem ser arremessados.</li>
<li>Se a skill for cancelada (Stun, morte), os alvos só são soltos, sem arremesso.</li>
<li>O grupo de colisão evita que os agarrados colidam entre si e com quem agarrou.</li>
</ul>`,
  });

  R("equipes", {
    title: "Times e cura em área", nivel: "Intermediário", lado: "Servidor",
    kw: "time times equipe team aliado fogo amigo cura em área heal aoe santuário affiliation",
    resumo: "Pôr os players em times (sem fogo amigo) e uma skill que cura aliados em volta de quem casta por 5 segundos.",
    arquivos: "<code>ServerScriptService/Times.server.luau</code> e <code>SkillDatabase/Schema/Santuario.luau</code> (novos).",
    links: ["conceitos.alvos", "api.StateTable.AffectsFilter", "api.Affiliation.SetTeam"],
    passos: [
      ["Dê um time a cada player", `<p>O <code>Main.server</code> não põe Affiliation no player. Este script espera a entidade nascer e adiciona o componente com o time do Roblox:</p>` + C(`
-- ServerScriptService/Times.server.luau
local Players = game:GetService("Players")
local DataManager = require(game.ServerScriptService.EntityData.DataManager)
local Component = require(game.ServerScriptService.EntityData.ComponentsExport)

local function aoNascer(player, character)
    if not character:GetAttribute("EntityID") then
        character:GetAttributeChangedSignal("EntityID"):Wait()
    end
    local e = DataManager.Get(character)
    if e and not e:HasComponent(Component.Affiliation) then
        e:AddComponent(Component.Affiliation, { Team = player.Team and player.Team.Name }, true)
    end
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character) aoNascer(player, character) end)
end)
`)],
      ["A skill de cura em área", C(REQ + `
local AreaEffect = require(game.ServerStorage.Modules.Combat.AreaEffect)

return {
    data = {
        cooldown = 15, duration = 5,
        affects = { Self = true, Ally = true, Enemy = false, Neutral = false },
    },
    callbacks = {
        onStart = function(self)
            local zona = AreaEffect.new(function() return self.Entity.GetCFrame() end, "Sphere", 12, 2)
            zona:SetFilter(StateTable.AffectsFilter(self))       -- usa o affects acima
            zona:OnStay(function(e)
                e.Heal(4, { Source = self.Runner })              -- 2 polls/s: 8 de cura por segundo
            end)
            zona:Start()
            self:Own(function() zona:Stop() end)
        end,
    },
}
`)],
    ],
    funciona: `<ul>
<li>Quem afeta quem é regra do StateTable: a relação é Self, Ally (mesmo time), Enemy ou Neutral (sem time). Por padrão (<code>Enum.AffectsDefaults</code>), hitboxes e zonas de skill não entregam aliados: não há fogo amigo sem mudar nada.</li>
<li>O <code>data.affects</code> da skill inverte a regra só para ela; o <code>AffectsFilter</code> aplica essa regra na zona, então inimigos nem chegam no <code>OnStay</code>.</li>
<li>Com <code>Source</code>, a cura credita quem casta (<span class="badge out">OUT</span> <code>OnHeal</code>), útil para placar de suporte.</li>
</ul>`,
  });

  R("recurso", {
    title: "Recurso (mana) sem componente novo", nivel: "Intermediário", lado: "Servidor (e a HUD no cliente)",
    kw: "mana energia recurso resource custo regeneração stamina",
    resumo: "Mana como stat do Attributes: custo por skill com devolução do cooldown quando falta, regeneração por status e a barra na HUD por atributo do Model.",
    arquivos: "<code>ServerScriptService/Mana.server.luau</code>, <code>StateTable/Status/Buffs/RegenMana.luau</code> e as skills que custam.",
    links: ["conceitos.stats", "api.Attributes.SetStat", "api.skill.Fizzle"],
    passos: [
      ["O status de regeneração", C(`
-- StateTable/Status/Buffs/RegenMana.luau: sem duração, roda enquanto a entidade existir
local Enum = require(script.Parent.Parent.Parent.Enum)
return {
    data = { name = "RegenMana", category = Enum.Categories.Internal, porSegundo = 8 },
    callbacks = {
        onStep = function(self, dt)
            local e = self.Entity
            local mana, max = e.GetStat("Mana", 0), e.GetStat("ManaMax", 100)
            if mana < max then
                local nova = math.min(max, mana + self.data.porSegundo * dt)
                e.SetStat("Mana", nova)
                -- a HUD só precisa de inteiros: não replica um atributo novo a cada frame
                if e.Instance and math.floor(nova) ~= math.floor(mana) then
                    e.Instance:SetAttribute("Mana", math.floor(nova))
                end
            end
        end,
    },
}
`)],
      ["Dê mana a cada player ao nascer", C(`
-- ServerScriptService/Mana.server.luau
local Players = game:GetService("Players")
local DataManager = require(game.ServerScriptService.EntityData.DataManager)
local StateTable = require(game.ServerStorage.Modules.Combat.StateTable)

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        if not character:GetAttribute("EntityID") then
            character:GetAttributeChangedSignal("EntityID"):Wait()
        end
        local e = DataManager.Get(character)
        if not e then return end
        e.SetStat("ManaMax", 100)
        e.SetStat("Mana", 100)
        character:SetAttribute("ManaMax", 100)
        character:SetAttribute("Mana", 100)
        e.ApplyStatus(StateTable.Status.RegenMana, {})
    end)
end)
`)],
      ["Cobre o custo na skill", C(`
data = { cooldown = 2, duration = 0.5, custo = 30 },
callbacks = {
    onStart = function(self)
        local mana = self.Entity.GetStat("Mana", 0)
        if mana < self.data.custo then return self:Fizzle() end   -- o cooldown volta
        self.Entity.SetStat("Mana", mana - self.data.custo)
        if self.Entity.Instance then self.Entity.Instance:SetAttribute("Mana", math.floor(mana - self.data.custo)) end
        -- ... o efeito da skill
    end,
},
`)],
      ["A barra (cliente)", C(`
-- LocalScript: barra é um Frame dentro de um fundo
local function ligar(character)
    local function atualizar()
        local m, max = character:GetAttribute("Mana") or 0, character:GetAttribute("ManaMax") or 100
        barra.Size = UDim2.fromScale(m / max, 1)
    end
    character:GetAttributeChangedSignal("Mana"):Connect(atualizar)
    atualizar()
end
game.Players.LocalPlayer.CharacterAdded:Connect(ligar)
if game.Players.LocalPlayer.Character then ligar(game.Players.LocalPlayer.Character) end
`)],
    ],
    funciona: `<ul>
<li>Um stat que o motor não conhece é só um nome no Attributes: base, modificadores (um buff de +50% de regeneração é um <code>AddModifier</code>) e limite (não fica negativo).</li>
<li><code>Fizzle</code> encerra com o motivo <code>fizzle</code>, que devolve o cooldown inteiro: sem mana, é como se o botão não tivesse sido apertado.</li>
<li>A HUD lê um atributo do Model, que replica sozinho. Quem decide é sempre o servidor.</li>
<li>Uma forma nova (SetCharMode) não mexe em stats que ela não declara: a mana sobrevive à troca.</li>
</ul>`,
  });

  R("global", {
    title: "Placar e kill feed", nivel: "Intermediário", lado: "Servidor",
    kw: "global placar kill feed abates mortes leaderstats qualquer entidade listenworld",
    resumo: "Contar abates e mortes de cada player no leaderstats e anunciar cada abate, reagindo a qualquer morte do jogo.",
    arquivos: "<code>ServerScriptService/Placar.server.luau</code> (novo).",
    links: ["api.EntityCore.ListenWorld", "api.StateTable.EffectOwner", "conceitos.morte"],
    passos: [
      ["Crie o leaderstats", C(`
-- ServerScriptService/Placar.server.luau
local Players = game:GetService("Players")
local EntityCore = require(game.ServerScriptService.EntityData.EntityCore)
local StateTable = require(game.ServerStorage.Modules.Combat.StateTable)
local Enum = StateTable.Enum

Players.PlayerAdded:Connect(function(player)
    local ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = player
    for _, nome in { "Abates", "Mortes" } do
        local v = Instance.new("IntValue"); v.Name = nome; v.Parent = ls
    end
end)
`)],
      ["Escute todas as mortes", C(`
local KillFeed = Instance.new("RemoteEvent")
KillFeed.Name = "KillFeed"
KillFeed.Parent = game.ReplicatedStorage.RemoteEvents

-- OUT: emitido no dono de quem matou (o matador)
EntityCore.ListenWorld({
    Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.OnDeath,
    Action = function(ctx, matador)
        local vitima = ctx.targetEntity
        if not (matador.Player and vitima) or vitima == matador then return end
        matador.Player.leaderstats.Abates.Value += 1
        KillFeed:FireAllClients(matador.Player.Name, vitima.Player and vitima.Player.Name or vitima.ID)
    end,
})

-- IN: emitido em quem morreu
EntityCore.ListenWorld({
    Role = Enum.Roles.IN, Breakpoint = Enum.Breakpoints.OnDeath,
    Action = function(ctx, morto)
        if morto.Player then morto.Player.leaderstats.Mortes.Value += 1 end
    end,
})
`)],
    ],
    funciona: `<ul>
<li><code>ListenWorld</code> recebe o canal de todas as entidades, com quem emitiu depois do contexto. Sem nenhum ouvinte no mundo, as mortes não pagam nada a mais.</li>
<li>O <span class="badge out">OUT</span> <code>OnDeath</code> vai para o dono do efeito: uma morte por veneno conta para quem envenenou, e um minion matando conta para o dono do runner (o minion, que não tem Player).</li>
<li>Morte sem matador (lava, queda) não emite OUT: só a coluna Mortes sobe.</li>
</ul>`,
  });

  // ================================================================ Avançado
  R("possessao", {
    title: "Controle mental (possessão)", nivel: "Avançado", lado: "Servidor",
    kw: "possessão controle mental mind control possuir dirigir corpo",
    resumo: "O player dirige o NPC clicado por 8 segundos e volta ao próprio corpo no fim, na morte do NPC ou se a skill for cancelada.",
    arquivos: "<code>SkillDatabase/Schema/Dominar.luau</code> (novo); os alvos precisam do componente Control.",
    links: ["conceitos.controle", "api.Control.Possess", "receitas.mira"],
    passos: [
      ["Ponha Control nos NPCs que podem ser dominados", C(`
DataManager.Create(model, {
    Component.Character, Component.Health, Component.Status, Component.Movement,
    Component.Combat, Component.AI, Component.Control,
}, { Combat = { ChosenChar = false }, AI = { Brain = brain } })
`)],
      ["Crie a skill", C(REQ + `

return {
    data = { cooldown = 20, duration = 8 },
    callbacks = {
        onStart = function(self, ctx)
            local alvo = ctx.input.Target and DataManager.Get(ctx.input.Target)
            if not (alvo and self.Entity.Player and alvo:HasComponent(Component.Control)) then
                return self:Fizzle()
            end
            if alvo.Possess({ Player = self.Entity.Player }) then
                self:Own(function() alvo.Release() end)
            else
                self:Fizzle()
            end
        end,
    },
}
`)],
    ],
    funciona: `<ul>
<li>Na possessão, o input do player (movimento, mira e skills) vai para o NPC, a IA dele é pausada, a rede do corpo passa ao cliente do player e a HUD mostra a vida do NPC.</li>
<li>O <code>Own</code> devolve em qualquer fim da skill; <code>ReleaseOnDeath</code> (padrão) devolve também se o NPC morrer.</li>
<li>O corpo original do player fica parado onde estava, e continua podendo apanhar.</li>
<li>As possessões ficam numa pilha por player: dominar outro NPC de dentro do primeiro e soltar volta para o primeiro.</li>
</ul>`,
  });

  R("roubar", {
    title: "Roubar a Ultimate do alvo", nivel: "Avançado", lado: "Servidor",
    kw: "roubar skill steal copiar herdar cooldown camada loadout",
    resumo: "Copiar a Ultimate do alvo para o slot Ability3 de quem casta por 15 segundos, com o cooldown que ela tinha, e devolver o slot no fim.",
    arquivos: "<code>SkillDatabase/Schema/Roubar.luau</code> (novo).",
    links: ["conceitos.loadout", "api.CooldownPolicy.Transfer", "api.Combat.GetSkillFromSlot"],
    passos: [
      ["Crie a skill", C(REQ + `
local Intents = require(game.ReplicatedStorage.Input.Intents)
local CooldownPolicy = require(game.ServerScriptService.Modules.CooldownPolicy)

return {
    data = { cooldown = 30, duration = 15 },
    callbacks = {
        onStart = function(self, ctx)
            local alvo = ctx.input.Target and DataManager.Get(ctx.input.Target)
            if not (alvo and alvo:HasComponent(Component.Combat)) then return self:Fizzle() end
            local roubada = alvo.GetSkillFromSlot(Intents.Id.Ultimate)
            if not roubada then return self:Fizzle() end

            self.Entity.EquipSkill(Intents.Id.Ability3, roubada, "Roubo")      -- camada própria
            CooldownPolicy.Transfer(alvo, self.Entity, roubada.data.name, "Copy")
            self:Own(function()
                if self.Entity.Active then self.Entity.RemoveLoadoutLayer("Roubo") end
            end)
        end,
    },
}
`)],
    ],
    funciona: `<ul>
<li>A skill roubada é a mesma tabela do alvo, com <code>data.name</code> e <code>data.kit</code> já carimbados: ela segue tocando as animações do kit dono, em qualquer corpo.</li>
<li>A camada <code>Roubo</code> fica por cima: só o slot Ability3 muda, e remover a camada devolve o que havia nele.</li>
<li><code>Transfer</code> copia o tempo restante e as cargas: se a Ultimate do alvo estava em cooldown, a roubada também está. Com <code>"Move"</code>, o alvo ficaria com a dele pronta.</li>
<li>O cooldown é guardado pelo nome da skill: se quem rouba já tem a mesma skill, as duas dividem o cooldown.</li>
<li>Skills de arma precisam da arma equipada (veja ${L("fluxo.limitacoes")}).</li>
</ul>`,
  });

  R("minion", {
    title: "Minion que herda reações", nivel: "Avançado", lado: "Servidor",
    kw: "minion lacaio invocar summon herdar inherit blueprint matilha pet",
    resumo: "Invocar um lobo do mesmo time, com uma IA simples, que herda o on-hit do invocador e some em 20 segundos.",
    arquivos: "<code>ServerStorage/Modules/MinionFactory/Blueprints/Lobo.luau</code> e <code>SkillDatabase/Schema/Invocar.luau</code> (novos).",
    links: ["conceitos.heranca", "api.MinionFactory.Spawn", "conceitos.ia"],
    passos: [
      ["O blueprint", C(`
-- MinionFactory/Blueprints/Lobo.luau
local SkillHandler = require(game.ServerScriptService.Modules.SkillHandler)
local Intents = require(game.ReplicatedStorage.Input.Intents)

local function brain(entity, dt)
    local alvo = entity.alvoDoLobo
    if not (alvo and alvo.Active and alvo.IsAlive()) then
        SkillHandler.HandleMovementInput(entity.ID, Vector3.zero)
        return
    end
    local delta = alvo.GetPosition() - entity.GetPosition()
    SkillHandler.HandleMovementInput(entity.ID, delta)
    if delta.Magnitude < 4 then   -- morde pelo mesmo caminho do player (o cooldown é da skill)
        SkillHandler.HandleIntent(entity.ID,
            Intents.NewEvent(Intents.Id.Primary, Intents.Kind.Activate, Intents.Gesture.Press))
    end
end

return {
    Components = { "Character", "Health", "Status", "Movement", "Attributes", "Combat", "Affiliation", "AI" },
    Configs = {
        Health = { MaxHP = 40 },
        Attributes = { BaseStats = { Speed = 22 } },
        Combat = { ChosenChar = false },         -- sem kit: a mordida é equipada na invocação
        AI = { Brain = brain },
    },
    Model = game.ServerStorage.Assets.Lobo,     -- um Model com HumanoidRootPart
}
`)],
      ["A skill de invocar", C(REQ + `
local MinionFactory = require(game.ServerStorage.Modules.MinionFactory)
local Intents = require(game.ReplicatedStorage.Input.Intents)

-- a mordida é uma skill de verdade: passa pelo OUT.onHit do lobo, onde está a reação herdada
local Mordida = {
    data = { name = "Lobo_Mordida", cooldown = 1, duration = 0.1 },
    callbacks = {
        onStart = function(self)
            local alvo = self.Entity.alvoDoLobo
            if alvo and alvo.Active and (alvo.GetPosition() - self.Entity.GetPosition()).Magnitude < 5 then
                self:Damage(alvo, 6)
            end
        end,
    },
}

return {
    data = { cooldown = 25, duration = 0.2 },
    callbacks = {
        onStart = function(self, ctx)
            -- reação herdável: os golpes do invocador (e do lobo) aplicam sangramento
            self.Entity:UnsubscribeByOwner(StateTable.OwnerToken(self.Entity, "Matilha"))
            self.Entity:Listen({
                Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.onHit,
                Owner = StateTable.OwnerToken(self.Entity, "Matilha"),
                Inherit = { Generations = 1 }, TTD = 20,
                Action = function(hitCtx) table.insert(hitCtx.effects, StateTable.Status.Bleed) end,
            })

            local lobo = MinionFactory.Spawn("Lobo", self.Entity.GetCFrame() * CFrame.new(3, 0, 0), self.Entity)
            if not lobo then return end
            if self.Entity:HasComponent(Component.Affiliation) then lobo.SetTeam(self.Entity.GetTeam()) end
            lobo.EquipSkill(Intents.Id.Primary, Mordida)
            lobo.alvoDoLobo = ctx.input and ctx.input.Target and DataManager.Get(ctx.input.Target)

            task.delay(20, function()
                if lobo.Active then
                    local corpo = lobo.Instance
                    DataManager.Remove(lobo)
                    if corpo then corpo:Destroy() end
                end
            end)
        end,
    },
}
`)],
    ],
    funciona: `<ul>
<li>O 3º argumento do <code>Spawn</code> faz o lobo nascer com uma cópia das reações do invocador marcadas com <code>Inherit</code>. Por isso a reação é inscrita antes do Spawn: o que for inscrito depois não chega ao lobo já criado.</li>
<li>A mordida é uma skill equipada no lobo: o <code>self:Damage</code> dela emite o <span class="badge out">OUT</span> <code>onHit</code> do lobo, onde a reação herdada põe o sangramento nos efeitos do golpe. Um <code>TakeDamage</code> direto pularia o lado do atacante e a herança não teria onde agir.</li>
<li>O Brain aperta o botão pelo SkillHandler, como um player: o cooldown de 1 s da mordida é o ritmo do ataque.</li>
<li>O alvo fica guardado na própria tabela da entidade (<code>alvoDoLobo</code>); use nomes que não colidam com a API dos componentes.</li>
<li><code>DataManager.Remove</code> não apaga o Model: o script destrói o corpo depois.</li>
</ul>`,
  });

  R("ia", {
    title: "IA completa de inimigo", nivel: "Avançado", lado: "Servidor",
    kw: "ia ai inimigo npc brain cérebro patrulha perseguir atacar fugir máquina de estados mob",
    resumo: "Um guarda que patrulha entre pontos, persegue o player mais próximo que vê, ataca com as skills do kit respeitando o cooldown e foge com pouca vida.",
    arquivos: "<code>ServerScriptService/Guardas.server.luau</code> (novo) e um Model de NPC com Humanoid.",
    links: ["conceitos.ia", "api.SkillHandler.HandleIntent", "api.Combat.HasCooldown"],
    passos: [
      ["Uma fábrica de cérebros", `<p>Cada guarda precisa do próprio estado; uma função que devolve um Brain novo guarda esse estado numa closure.</p>` + C(`
-- ServerScriptService/Guardas.server.luau
local Players = game:GetService("Players")
local DataManager = require(game.ServerScriptService.EntityData.DataManager)
local Component = require(game.ServerScriptService.EntityData.ComponentsExport)
local SkillHandler = require(game.ServerScriptService.Modules.SkillHandler)
local StateTable = require(game.ServerStorage.Modules.Combat.StateTable)
local Intents = require(game.ReplicatedStorage.Input.Intents)

local VISAO, ALCANCE_GOLPE = 40, 6

local function apertar(entity, intent)
    SkillHandler.HandleIntent(entity.ID, Intents.NewEvent(intent, Intents.Kind.Activate, Intents.Gesture.Press))
end

local function playerMaisProximo(entity)
    local melhor, dist = nil, VISAO
    for _, p in Players:GetPlayers() do
        local id = p:GetAttribute("EntityID")
        local e = DataManager.Exists(id) and DataManager.Get(id)
        if e and e.IsAlive() and StateTable.CanAffect(entity, e) then
            local d = (e.GetPosition() - entity.GetPosition()).Magnitude
            if d < dist then melhor, dist = e, d end
        end
    end
    return melhor
end

local function criarBrain(pontos)
    local estado, alvo, indice, procura = "Patrulha", nil, 1, 0
    return function(entity, dt)
        procura -= dt
        if procura <= 0 then                       -- procurar alvo 4x por segundo, não a cada frame
            procura = 0.25
            alvo = playerMaisProximo(entity)
        end
        if entity.GetHealthRatio() < 0.25 and alvo then
            estado = "Fuga"
        elseif alvo then
            estado = "Ataque"
        else
            estado = "Patrulha"
        end

        if estado == "Patrulha" then
            local destino = pontos[indice].Position
            local delta = destino - entity.GetPosition()
            if Vector3.new(delta.X, 0, delta.Z).Magnitude < 2 then indice = indice % #pontos + 1 end
            SkillHandler.HandleMovementInput(entity.ID, delta)
        elseif estado == "Ataque" then
            local delta = alvo.GetPosition() - entity.GetPosition()
            SkillHandler.HandleLookInput(entity.ID, delta)
            if delta.Magnitude > ALCANCE_GOLPE then
                SkillHandler.HandleMovementInput(entity.ID, delta)
                if delta.Magnitude > 15 and not entity.HasCooldown("Schema_Dash") then
                    apertar(entity, Intents.Id.Dash)
                end
            else
                SkillHandler.HandleMovementInput(entity.ID, Vector3.zero)
                apertar(entity, Intents.Id.Primary)  -- o motor recusa se estiver em cooldown
            end
        else -- Fuga
            SkillHandler.HandleMovementInput(entity.ID, entity.GetPosition() - alvo.GetPosition())
        end
    end
end
`)],
      ["Crie os guardas", C(`
for _, model in workspace.Guardas:GetChildren() do
    local pontos = model:FindFirstChild("Pontos") and model.Pontos:GetChildren() or { model.PrimaryPart }
    DataManager.Create(model, {
        Component.Character, Component.Health, Component.Status, Component.Movement,
        Component.Attributes, Component.Combat, Component.Animation, Component.Weapon,
        Component.Affiliation, Component.AI,
    }, {
        Health = { MaxHP = 150 },
        Combat = { ChosenChar = "Schema" },          -- o kit da Schema: M1, Dash, arma
        Affiliation = { Team = "Guardas" },
        AI = { Brain = criarBrain(pontos) },
    })
end
`)],
    ],
    funciona: `<ul>
<li>O Brain só produz input, pelo mesmo caminho do player: canCast, Stun, cooldown e ActionState valem igual para o guarda. Por isso ele pode "apertar" o M1 todo frame no alcance: o motor recusa enquanto o golpe não está pronto.</li>
<li>Todos os Brains rodam num Heartbeat único; a busca de alvo é espaçada (4x por segundo) porque varrer os players a cada frame em cada guarda não escala.</li>
<li><code>CanAffect(entity, e)</code> usa os times: os players precisam de Affiliation num time diferente (${L("receitas.equipes")}) ou nenhum (Neutral), para o guarda os considerar alvo.</li>
<li>Um player possuindo um guarda pausa o Brain; o Release devolve.</li>
</ul>`,
    variacoes: `<ul>
<li>Pathfinding: calcule o caminho com o PathfindingService e mande a direção até o próximo waypoint no lugar do <code>delta</code>.</li>
<li>Skills de Hold na IA: Activate com <code>Gesture.Hold</code>, espere, e mande o Release (${L("api.SkillHandler.HandleIntent")}, exemplo 2).</li>
</ul>`,
  });

  R("personagem", {
    title: "Criar um personagem", nivel: "Avançado", lado: "Servidor",
    kw: "criar personagem kit char novo herói ronin forma",
    resumo: "Um kit novo (Ronin) nos quatro lugares em que um personagem vive: forma, skills, arma e animações, e como o player passa a usá-lo.",
    arquivos: "<code>CharacterDatabase/Ronin/Base.luau</code>, <code>SkillDatabase/Ronin/*</code>, <code>Assets/Weapons/Ronin/Katana/</code> e <code>AnimationLib</code>.",
    links: ["conceitos.personagens", "api.Combat.SetCharMode", "api.Weapon.EquipWeapon"],
    passos: [
      ["As skills", `<p>Crie a pasta <code>ServerStorage/DataBase/SkillDatabase/Ronin</code> e ponha as skills nela (siga ${L("receitas.skill")}). A pasta faz do Ronin o kit dono: as chaves ficam <code>Keys.Ronin.Corte</code>, <code>Keys.Ronin.Investida</code>...</p>`],
      ["As animações", C(`
-- ServerStorage/Modules/Animation/AnimationLib: dentro de lib.character
Ronin = {
    M1 = { Corte1 = "1234567890", Corte2 = "1234567891" },
    Investida = { Inicio = "1234567892" },
},
`) + `<p>Nas skills do Ronin: <code>self.charLib.M1.Corte1</code>.</p>`],
      ["A arma", `<p>Em <code>ReplicatedStorage/Assets/Weapons/Ronin/Katana/</code>: o Model <code>Katana</code> (com <code>Handle</code>, <code>hitOrigin</code> e a pasta <code>Hitbox</code>) e o módulo <code>WeaponData</code>. A estrutura do Model está em ${L("conceitos.personagens")}.</p>` + C(`
-- Assets/Weapons/Ronin/Katana/WeaponData.luau
return {
    BaseName = "Katana",
    DefaultMode = "Uma",
    Modes = {
        Uma = { AttachPoints = { primary = "Right Arm" } },
    },
}
`)],
      ["A forma", C(`
-- ServerStorage/DataBase/CharacterDatabase/Ronin/Base.luau
local Intents = require(game.ReplicatedStorage.Input.Intents).Id
local Keys = require(game.ServerStorage.DataBase.SkillDatabase).Keys

return {
    Stats = { MaxHP = 90, Speed = 22, JumpForce = 12 },
    Loadout = {
        Slots = {
            [Intents.Primary] = Keys.Ronin.Corte,
            [Intents.Dash] = Keys.Schema.Dash,          -- skill de outro kit também vale
            [Intents.Ability1] = Keys.Ronin.Investida,
        },
    },
    Weapon = "Katana",
    attachTo = "Right Arm",
}
`)],
      ["Use o personagem", `<p>Todos os players começam como Ronin trocando o padrão do motor em <code>Enum.CombatDefaults</code>:</p>` + C(`
enum.CombatDefaults = table.freeze({
    ChosenChar = "Ronin",
    Mode = "Base",
})
`) + `<p>Ou troque um player em jogo (escolha de personagem):</p>` + C(`
local e = DataManager.Get(player)
e.SetCharMode("Ronin", "Base")       -- stats e loadout
e.UnequipWeapon()
e.EquipWeapon("Katana", "Ronin")     -- a arma não troca sozinha
`)],
    ],
    funciona: `<ul>
<li>O kit é o nome da pasta, igual nos quatro lugares. É por ele que a skill acha as animações (<code>data.kit</code>), que a arma é procurada e que a forma é carregada.</li>
<li><code>SetCharMode</code> aplica os Stats (MaxHP mantendo a porcentagem de vida) e põe o Loadout na camada Base; a arma é do componente Weapon e troca à parte.</li>
<li>Para skill que depende de animação ou de arma, declare <code>requires = { Component.Animation, Component.Weapon }</code>: numa entidade sem eles, o motor recusa o cast em vez de dar erro.</li>
</ul>`,
  });

  R("cardgame", {
    title: "Esqueleto de card game", nivel: "Avançado", lado: "Servidor",
    kw: "card game carta baralho deck mão turno tabuleiro jogo de cartas",
    resumo: "Jogadores e mesa como entidades de dado, turnos como breakpoints próprios, o efeito de cada carta como uma skill e status que duram turnos.",
    arquivos: "Um módulo do jogo (ex.: <code>ServerScriptService/CardGame</code>).",
    links: ["api.DataManager.CreateData", "api.EntityCore.Emit", "api.SkillRunner.new"],
    passos: [
      ["Mesa e jogadores", C(`
local DataManager = require(game.ServerScriptService.EntityData.DataManager)
local Component = require(game.ServerScriptService.EntityData.ComponentsExport)
local StateTable = require(game.ServerStorage.Modules.Combat.StateTable)
local Enum = StateTable.Enum

local mesa = DataManager.CreateData({})        -- só o barramento dos eventos da partida

local function novoJogador(time)
    return DataManager.CreateData(
        { Component.Health, Component.Status, Component.Attributes, Component.Combat, Component.Affiliation },
        {
            Health = { MaxHP = 30 },
            Attributes = { BaseStats = { Mana = 0 } },
            Combat = { ChosenChar = false },
            Affiliation = { Team = time },
        })
end
local azul, vermelho = novoJogador("Azul"), novoJogador("Vermelho")
`)],
      ["Turnos como eventos", C(`
local turno = 0
local function passarTurno(jogador)
    mesa:Emit(Enum.Roles.OUT, "OnTurnEnd", { jogador = jogador }, turno)
    turno += 1
    jogador.SetStat("Mana", math.min(10, turno))
    mesa:Emit(Enum.Roles.OUT, "OnTurnStart", { jogador = jogador }, turno)
end
`)],
      ["O efeito da carta é uma skill", C(`
local SkillRunner = require(game.ServerScriptService.Modules.SkillRunner)
local SkillFactory = require(game.ServerScriptService.Modules.SkillFactory)

local BolaDeFogo = {
    data = { name = "BolaDeFogo", custo = 3, traits = { "Feitiço" } },
    callbacks = {
        onStart = function(self, ctx)
            self:Damage(ctx.inherited.alvo, 5)
            self:Stop(false)
        end,
    },
}

local function jogarCarta(jogador, carta, alvo)
    local mana = jogador.GetStat("Mana", 0)
    if mana < carta.data.custo then return false end
    jogador.SetStat("Mana", mana - carta.data.custo)
    local runner = SkillRunner.new(SkillFactory.GetSkill(carta), jogador, carta.data.name,
        Enum.Types.Skill, nil, nil, { alvo = alvo })
    runner:start()
    mesa:Emit(Enum.Roles.OUT, "OnCardPlayed", { traits = carta.data.traits, carta = carta, jogador = jogador })
    return true
end
`)],
      ["Status que dura turnos", C(`
-- "Congelado por 2 turnos": status sem duração, removido por quem conta os turnos
local function congelar(alvo, turnos)
    local id = alvo.ApplyStatus(StateTable.States.Stun, {})
    local restantes = turnos
    local sair
    sair = mesa:Listen({
        Role = Enum.Roles.OUT, Breakpoint = "OnTurnEnd",
        Action = function(ctx)
            if ctx.jogador ~= alvo then return end
            restantes -= 1
            if restantes <= 0 then
                alvo.RemoveStatusByID(id)
                sair()
            end
        end,
    })
end
`)],
    ],
    funciona: `<ul>
<li>Entidades de dado (<code>CreateData</code>) têm vida, status, stats, time e loadout, sem corpo: tudo o que o motor faz com dano, morte, cura e status vale para elas.</li>
<li>Os turnos são breakpoints próprios do jogo, emitidos na mesa. Cartas com "no início do turno..." são listeners de <code>OnTurnStart</code> (com <code>Owner</code> da carta, para sair quando ela for descartada).</li>
<li>O efeito da carta roda como uma skill do jogador: dano, crédito de morte, <code>OUT.onHit</code> e cadeias funcionam como no combate. O alvo vai no <code>inherited</code> (só leitura).</li>
<li>Mão, baralho e cemitério são tabelas do jogo: não precisam ser entidades.</li>
</ul>`,
  });
})();

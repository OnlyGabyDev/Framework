/* Receitas: casos reais só com a API pública. Várias ainda em rascunho (ver docs/PENDENTE.md). */
(function () {
  function R(id, title, kw, lead, html) {
    DOCS.page({ id: "receitas." + id, parent: "receitas", title: title, kw: kw, lead: lead, html: html || "" });
  }
  DOCS.page({
    id: "receitas", title: "Receitas", kw: "receitas exemplos como fazer tutorial cookbook",
    lead: "Mecânicas comuns resolvidas só com a API pública, sem mexer no motor.",
    html: N("<p>Algumas receitas ainda estão em rascunho e apontam para a página do guia onde o código já existe.</p>"),
  });

  R("skill", "Sua primeira skill", "primeira skill criar skill golpe melee tutorial",
    "Um golpe com hitbox da arma, dano e Stun curto, equipado num slot.",
    C(`
-- ServerStorage/DataBase/SkillDatabase/Schema/Soco.luau
local StateTable = require(game.ServerStorage.Modules.Combat.StateTable)
local Component = require(game.ServerScriptService.EntityData.ComponentsExport)
return {
    data = { cooldown = 1.5, duration = 0.4, traits = { StateTable.Enum.Traits.Melee },
             requires = { Component.Weapon }, damage = 10 },
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
`) + C(`
-- equipar (ou ponha no Loadout da forma no CharacterDatabase)
local Keys = require(game.ServerStorage.DataBase.SkillDatabase).Keys
entity.EquipSkill(Intents.Id.Ability2, Keys.Schema.Soco)
`) + "<p>Veja " + L("conceitos.skills") + " e " + L("api.skill.data") + ".</p>");

  R("hold", "Skill carregada (hold)", "carregar charge hold segurar soltar onrelease heldtime",
    "Segurar para carregar, soltar para disparar com força proporcional.",
    C(`
data = { cooldown = 3, duration = 5, input = { Hold = 0.25, Tap = true } },
callbacks = {
    onStart = function(self, ctx)
        self.carregando = ctx.input.Gesture == Intents.Gesture.Hold
        if not self.carregando then self:Stop(false) end  -- toque curto: ação rápida aqui
    end,
    onRelease = function(self, ctx)
        local carga = math.clamp(ctx.input.HeldTime / 2, 0.2, 1)
        -- dispara com 'carga' (ex.: Presets.HomingBolt com dano * carga)
        self:Stop(false)
    end,
},
`));

  R("projetil", "Projétil teleguiado", "projétil projectile homing teleguiado bola de fogo tiro",
    "Hitbox solta pelo HitboxPresets, com filtro de time e um acerto por alvo.",
    C(`
local Presets = require(game.ServerStorage.Modules.Combat.Hitbox.HitboxPresets)
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
            hitbox:HitStop()
        end
    end)
end,
`));

  R("dot", "Veneno (DoT com stacks)", "dot veneno poison sangramento bleed queimadura stack",
    "Um status de dano periódico com stacks, aplicado em todo acerto da skill.",
    "<p>O status está em " + L("conceitos.status") + " (seção “Status com dano periódico”). Para aplicar em todo hit: <code>data.effects = { StateTable.Status.Poison }</code> na skill.</p>");

  R("parry", "Parry", "parry aparar contra-ataque reflexo refletir",
    "Uma janela curta que cancela o próximo dano e atordoa quem bateu.",
    C(`
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
`) + "<p>Refletir dano entre dois parries é uma cadeia: os " + L("conceitos.cadeias", "limites de cadeia") + " cortam o ping-pong.</p>");

  R("lifesteal", "Roubo de vida", "lifesteal roubo de vida vampirismo curar ao bater",
    "Cura uma fração do dano causado, sem contar DoT.",
    C(`
entity:Listen({
    Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.OnDamage,
    Query = { None = { Enum.Traits.DOT } },
    Owner = StateTable.OwnerToken(entity, "Lifesteal"),
    Action = function(ctx) entity.Heal((ctx.actualDamage or 0) * 0.2) end,
})
`));

  R("sobrevida", "Sobrevida (overheal)", "sobrevida overheal escudo de vida hp acima do máximo",
    "HP acima do MaxHP é permitido: cure com teto maior ou defina o HP.",
    C(`
alvo.Heal(50, { Cap = 1.5 })          -- até 150% do MaxHP
alvo.SetHP(alvo.GetMaxHP() + 30)      -- valor exato, sem corte
`) + "<p>Para a sobrevida decair, um status cujo onStep reduz o excedente com <code>SetHP</code>. Veja " + L("conceitos.cura") + ".</p>");

  R("combo", "Combo entre skills", "combo sequência janela combowindow encadear",
    "A skill A abre uma janela; a B lê e consome, sem uma conhecer a outra.",
    C(`
-- skill A, num acerto
ComboWindow.Mark(self.Entity, "Lancamento", 1.2, { alvo = hit.target }, self.Runner)
-- skill B, no onStart
local combo = ComboWindow.Consume(self.Entity, "Lancamento")
if combo then self:Damage(combo.alvo, 40) end
`));

  R("vento", "Zona de vento", "vento ventilador zona empurrar corrente área",
    "Uma zona que empurra enquanto a entidade está dentro.",
    "<p>Código completo em " + L("conceitos.zonas") + ".</p>");

  R("agarrao", "Agarrão", "agarrão grab carregar segurar attachto levar junto",
    "Agarrar o alvo e levá-lo junto sem atraso, soltando no fim da skill.",
    C(`
onHit = function(self, hit)
    local release = hit.target.AttachTo(self.Entity.GetRoot(), CFrame.new(0, 0, -4))
    if not release then return end
    local restore = CollisionGroups.Assign(hit.target.Instance, CollisionGroups.Grabbed)
    self:Own(function() release(); restore() end)   -- solta em qualquer fim
end,
`) + "<p>A Ultimate da Schema é a referência completa.</p>");

  R("minion", "Minion que herda reações", "minion lacaio invocar summon herdar inherit",
    "Invocar um lacaio que herda o on-hit do invocador.",
    "<p>Veja " + L("conceitos.heranca") + " e " + L("api.MinionFactory") + ".</p>");

  R("possessao", "Controle mental (possessão)", "possessão controle mental mind control possuir",
    "O player dirige o alvo por alguns segundos.",
    C(`
onStart = function(self, ctx)
    local alvo = ctx.input.Target and DataManager.Get(ctx.input.Target)
    if not (alvo and self.Entity.Player and alvo:HasComponent(Component.Control)) then return self:Fizzle() end
    if alvo.Possess({ Player = self.Entity.Player }) then
        self:Own(function() alvo.Release() end)
    end
end,
data = { cooldown = 20, duration = 8 },
`));

  R("roubar", "Roubar skill com o cooldown", "roubar skill steal copiar herdar cooldown",
    "Equipar a skill do alvo numa camada e levar o cooldown junto.",
    "<p>Veja " + L("api.CooldownPolicy.Transfer") + " e " + L("conceitos.loadout") + ".</p>");

  R("mira", "Mira com alvo e ponto", "mira alvo ponto target point mouse chão payload",
    "Mandar o alvo e o ponto do mouse junto com o input.",
    "<p>Código cliente e servidor em " + L("conceitos.input") + " (seção “Alvo e ponto”).</p>");

  R("global", "Evento global (placar, kill feed)", "global placar kill feed qualquer entidade listenworld",
    "Reagir a qualquer morte do jogo.",
    "<p>Veja " + L("api.EntityCore.ListenWorld") + ".</p>");

  R("recurso", "Recurso (mana) sem componente novo", "mana energia recurso resource custo",
    "Custo de skill num stat, com devolução do cooldown quando falta recurso.",
    C(`
-- entidade: Attributes = { BaseStats = { Mana = 100 } }
onStart = function(self)
    local mana = self.Entity.GetStat("Mana", 0)
    if mana < self.data.cost then return self:Fizzle() end  -- o cooldown volta (refund fizzle)
    self.Entity.SetStat("Mana", mana - self.data.cost)
    if self.Entity.Instance then self.Entity.Instance:SetAttribute("Mana", mana - self.data.cost) end -- HUD
end,
`));

  R("cardgame", "Esqueleto de card game", "card game carta baralho deck mão turno tabuleiro",
    "Cartas, mão e turno como entidades de dado; efeitos de carta como skills.",
    `<ul>
<li>Jogador e cartas no tabuleiro: ${L("api.DataManager.CreateData", "CreateData")} com Health, Status, Attributes (Custo, Ataque) e Affiliation.</li>
<li>Efeito de carta: um módulo de skill (onStart faz o efeito com <code>self:Damage</code>/<code>self:ApplyStatus</code>); custo pela receita de ${L("receitas.recurso", "recurso")}.</li>
<li>Turno: uma entidade gerente que emite breakpoints próprios (<code>OnTurnStart</code>, <code>OnTurnEnd</code>); cartas com “no início do turno” escutam com Listen/ListenWorld.</li>
<li>Duração em turnos: status sem duração, removido por um listener de <code>OnTurnEnd</code> que conta.</li>
<li>Alvo escolhido pelo player: o <code>Target</code> do payload.</li>
</ul>`);

  R("personagem", "Criar um personagem", "criar personagem kit char novo herói",
    "Um kit novo nas quatro pastas, com forma, skills, arma e animações.",
    "<p>Estrutura completa em " + L("conceitos.personagens") + ". Para o player usar o kit, passe <code>{ Combat = { ChosenChar = \"MeuKit\" } }</code> como configs no <code>DataManager.Create</code> do <code>Main.server</code>, ou troque <code>Enum.CombatDefaults.ChosenChar</code>.</p>");
})();

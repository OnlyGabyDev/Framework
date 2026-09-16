_Parte 2 de 4 do contexto do projeto — ver 00-identidade-e-regras.md para identidade, estilo de trabalho e as 20 regras do framework._

## Arquitetura Atual (visão geral)

- **EntityCore**: núcleo genérico. Componentes se auto-registram escaneando uma
  pasta; cada componente expõe API injetada diretamente na entidade
  (`self[funcName] = ...`). Stub silencioso (`warn` + `nil`) para componente
  ausente — aceitável durante sprint ativa (o warn aparece no console), mas
  insuficiente entre sprints, daí a regra 16: o sintoma pode aparecer longe da
  causa em outro fluxo/sessão.
- **StateTable**: dado centralizado de Buffs/Debuffs/States/PlayerStates/Enums,
  carregado dinamicamente via `Helper.LoadModules`.
- **SkillRunner + SkillScheduler**: todo runner (skill OU status) passa pelo
  mesmo objeto e mesmo heartbeat central — sendo reescrito (ver seção de Design
  Decidido abaixo).
- **ShapecastHitbox**: biblioteca separada, Solver/Visualizer despachado por
  ClassName/CastType — melhor exemplo atual de "módulo burro" (regra 15).
- **HitboxWrapper**: pooling global de hitboxes por `Instance:GetFullName()`.
- **Components existentes**: Combat, Status, Health, Weapon, Movement,
  Character, Animation, Attributes. (Attributes existe como módulo mas não está
  registrado em runtime — ver Bug 1.)

---

## Design Decidido (não reabrir sem justificativa técnica nova)

### Skills como classes isoladas (substituindo `Utils.copySkill`)

- `Utils.copySkill` está sendo **removido por completo**. Ele resolvia o
  problema errado: copiava a tabela `data`/`callbacks` por fora, mas nunca
  isolava upvalues/globals soltas dentro dos próprios callbacks (bug real
  confirmado em `Dash.module.luau`: `stateID`, `root`, `dashDir` declaradas sem
  `local`/`self.`, causando corrupção de estado entre execuções concorrentes da
  mesma skill).
- **Divisão de responsabilidade** (`SkillRunner` ≠ `Skill`):
  - `SkillRunner` = orquestrador puro de lifecycle (state machine: Idle/
    Casting/Running/Ended, `elapsedTime`, `connection` com o Scheduler,
    `ChainHistory` como preocupação de motor — decide corte por
    `MAX_RECURSION`).
  - `Skill` = instância isolada por ativação, dona exclusiva do estado de
    domínio (tudo que o autor da skill escreve: `stateID`, `root`, `damage`,
    `counter`, etc.). Criada via `setmetatable({}, { __index = skillModule })`
    — `__index` resolve `data`/`callbacks` estáticos até serem sobrescritos na
    própria instância. `skillModule` (o ModuleScript original, requerido uma
    vez) nunca é mutado em runtime.
  - `SkillRunner` guarda só um ponteiro pra instância de `Skill` (`self.skill`).
    Nenhuma herança por metatable entre instâncias de `Skill` diferentes — só
    entre a instância e seu próprio módulo estático de definição.
  - **`data` é estritamente estático/config** (cooldown, duration, castTime).
    Nunca escrito em runtime. `ChainHistory` não pertence a `data` — vive no
    `SkillRunner` e é exposto à Skill somente como leitura via `Context`.
- **Verificar durante implementação**: `SkillFactory.GetSkill` hoje seta
  `setmetatable(skill.callbacks, {__index = SkillDefaults})` e
  `skill.data.maxInstances = 1` diretamente no módulo requerido (cacheado). Isso
  é compatível com "data estritamente estático" (é configuração de fallback,
  seta uma vez, idempotente) — mas confirmar que a ordem de operações
  (Factory prepara o módulo estático → SkillRunner instancia via `__index`)
  não quebra ao integrar com o novo fluxo.
- **Achado de revisão relevante para esta migração**: `Dash.module.luau`
  referencia `self.cd` e `self.ED`, que não existem na API atual do
  EntityCore/componentes (o padrão vigente, usado em `M1.module.luau`, é
  `self.Entity`). Indica que Dash ficou para trás de um refactor de
  nomenclatura anterior. A migração para classe isolada é o momento de corrigir
  isso junto — não só o vazamento de globals, também a API desatualizada.
- **Enforcement complementar**: rodar Selene (linter Luau) com regra de globals
  implícitas ativa, como parte do checklist de fim de sprint (regra 19).

### Contexto por Breakpoint (substitui herança prototípica entre skills)

- **Herança via `__index` encadeado entre instâncias de skill foi descartada.**
  Motivo: cria acoplamento de lifetime (filho depende da tabela do pai
  continuar válida), vaza campos irrelevantes do pai pro filho, e é tudo-ou-nada
  (não dá pra herdar só `onHit` sem herdar o resto). Viola diretamente a regra 20.
- **Solução**: um objeto de `Context`, construído e injetado explicitamente a
  cada breakpoint (`onHit`, `onTrigger`, `onEnd`, etc.), nunca por referência
  viva a um runner "ancestral".
- **Shape do Context (dono único — regra 17, não redeclarar em outro lugar)**:

```lua
Context = {
    depth = number,              -- profundidade da cadeia de invocação
    history = {string, ...},     -- trilha de nomes (rootSkill -> ... -> atual)
    rootOrigin = Entity,         -- quem originou a cadeia
    sourceRunner = SkillRunner,  -- runner imediatamente anterior (não o root)
    inherited = {                -- payload explícito, decidido no ponto de injeção
        [string]: any
    },
}
```

- `inherited` só carrega o que o autor da skill-pai decidiu explicitamente
  passar adiante — nunca o `self` inteiro do pai.
- Lógica condicionada por profundidade (ex: "minion só spawna filho até depth 3")
  lê `context.depth` diretamente, sem caminhar cadeia de metatables.
- **Este mesmo mecanismo é a base do sistema de pub/sub (Objetivos 1 e 2
  abaixo)**: antes de uma skill disparar um breakpoint pro mundo externo, o
  `Context` passa por uma camada de checagem (string, tipo de dano, tags) que
  pode injetar/modificar `context.inherited` antes do callback final rodar.
  Não são dois sistemas — é o mesmo `Context` servindo dois propósitos
  (propagação de comportamento herdado + interceptação de output).

---

## Padronização de Nomenclatura — Prioridade Máxima

Achado de revisão: partes do framework nomeadas como se fossem exclusivas de
players, quando na prática são genéricas e usadas por qualquer entidade com
`CombatComponent` — players e NPCs igualmente. Isso viola a regra 3 (o
framework não pressupõe estilo/atores específicos) e é terreno fértil pra uma
violação futura da regra 20: nomear algo como "Player" convida um
desenvolvedor a colocar `IsPlayer()` em volta de um conceito que não tem nada
de exclusivo de player.

**Localizações confirmadas:**
- `Enum.Categories.Player = "PlayerState"` (`StateTable/Enum.module.luau`).
- Pasta/tabela `PlayerStates` inteira (`StateTable/PlayerStates/`, com
  `Self.selfCast`, `Self.globalCast`, `Out.cast`, `Out.globalCast`,
  `LockedCast`), carregada em `StateTable.PlayerStates`.
- Tipo `PlayerStatesType` (declarado em `CombatComponent.module.luau`).
- Campo `self.PlayerState` e métodos `SetPlayerState`/`GetPlayerState`/
  `RemovePlayerState` em `CombatComponent` — expostos via `ExposeAPI` pra
  qualquer entidade com o componente, não só `Player`.
- Uso em schemas de skill: `M1.module.luau` (`statsTable.PlayerStates.Out.
  cast`) e `Dash.module.luau` (`statsTable.PlayerStates.Self.selfCast`) —
  skills que qualquer entidade, NPC incluso, pode executar.

**O que o conceito realmente representa**: não é "estado do player", é a
**trava de execução exclusiva** de uma ação (a entidade pode auto-cancelar
essa ação pra castar outra, ou está travada por algo externo). Se aplica
igualmente a um boss NPC executando skill quanto a um jogador.

**Por que é prioridade máxima e não só cosmético**: cada skill nova escrita
referenciando `PlayerStates.X` é mais um call site pra migrar depois. Como o
projeto é sprint-based (regra 7, um módulo por vez) e o database de skills só
tende a crescer, essa dívida de nome cresce linearmente — mais barato corrigir
agora do que depois que dezenas de skills dependerem do nome errado.

**Direção sugerida (confirmar nome final com o desenvolvedor antes de
implementar — é uma mudança de superfície ampla)**: renomear a categoria/pasta
para algo neutro tipo `CastLock` ou `ExecutionLock`, mantendo os subgrupos
internos (`Self`/`Out`/`LockedCast`, que já são neutros) e ajustando os
métodos do `CombatComponent` para `SetCastLock`/`GetCastLock`/`RemoveCastLock`.
Não executar a renomeação sem validar o nome final — múltiplos arquivos
dependem disso, então vale fechar a nomenclatura antes de tocar código.

---


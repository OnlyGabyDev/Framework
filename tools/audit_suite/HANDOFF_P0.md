# Handoff — lote P0 da auditoria do framework de combate

Você vai aplicar o lote P0 (as correções que derrubam o servidor ou o player) da auditoria de
15/10/2026. Trabalhe um item por vez, prove cada correção com o teste indicado e reporte ao
usuário em português, de forma direta: ele quer críticas, não elogios.

## Contexto em 1 minuto

- Repo Roblox/Luau. `sync/` espelha o place **UNTOLD BATTLEGROUNDS** (placeId 114873614457629)
  por uma ferramenta de sync. **O place no Studio é a fonte da verdade.**
- Auditoria completa (74 falhas F01–F74): https://claude.ai/code/artifact/46b99f1b-a621-440c-a492-107e7e5c1e9f
  — leia com o conector Claude Docs se você tiver; senão peça ao usuário um export em Markdown.
- Regras do framework: **leia `.agents/rules/00` a `03` antes de tudo.** São 20 regras; trate como
  não negociáveis. As que mais pesam aqui: 1 (DRY), 7 (um módulo por vez), 12 (nada de campos
  soltos), 16/20 (dependência entre componentes explícita ou eliminada), 17 (formato com dono único),
  18 (debug padronizado), 19 (nomes duplicados são bug).
- Testes: `tools/audit_suite/`. O `README.md` dali explica como rodar e o valor esperado de cada teste.

## Antes de editar qualquer coisa

1. **Pergunte o sentido do sync** (Studio → disco ou mão dupla). Se for só Studio → disco, edite
   pelo MCP do Studio (`script_read` / `multi_edit`) e deixe o sync escrever o disco.
2. **Working tree tem mudanças que não são suas**: 82 `.luau` só com fim de linha, `sourcemap.json`
   e `sync/ReplicatedStorage/Assets/Weapons/Schema/martelo/WeaponData.luau` apagado pelo sync
   (o Studio tem duas pastas `Martelo`). Não restaure, não apague e não commite isso sem perguntar.
3. **Sem commit/push** até o usuário pedir.
4. **Decisões que são do usuário** — pergunte (AskUserQuestion) antes de implementar o item afetado:
   - a. F05, autoridade de movimento: (A) corpo server-owned com predição no cliente, ou
     (B) corpo do cliente com validação de velocidade/teleporte e correção no servidor.
     Existe um comentário aberto no doc pedindo essa escolha.
   - b. F21, possessão aninhada: **pilha** (Release volta ao corpo anterior) ou **troca**
     (Release sempre volta ao corpo nativo).
   - c. Se `Possess({Player = ...})` deve pausar a IA do alvo. Hoje não pausa por decisão do
     Sprint 15 (ver `sprints.md`); a auditoria aponta como armadilha.

## Itens do lote (nesta ordem)

### 1. F01 — vazamento do `MAX_RECURSION` global

- Onde: `sync/ServerStorage/Modules/Combat/StateTable/Helper.luau:46-58` (contador),
  `sync/ServerScriptService/EntityData/Components/HealthComponent.luau:75-87`,
  `sync/ServerScriptService/EntityData/Components/StatusComponent.luau:105-115`.
- Problema: qualquer erro dentro de `_TakeDamageInner`/`_ApplyStatusInner` (status malformado,
  `onTrigger` de block com erro, closure velha depois de `RemoveComponent`) pula o `ExitChain`.
  Depois de 50 erros, **todo** dano e status do servidor são recusados com `MaxRecursion`.
- Correção: rodar o miolo com `xpcall(..., debug.traceback)`, chamar `ExitChain()` sempre, e em erro
  fazer warn com o prefixo de debug combinado e retornar `false, "Error"`. Avalie levar a
  profundidade no context em vez de um contador global.
- Prova: BatchA T14 (auditoria: 10 de 10 vazaram e entidade saudável recebeu `false/MaxRecursion`;
  esperado: 0 vazamentos) e T02.

### 2. Status — F06, F07, F08, F09, F39

- F06 `RemoveStatus` (`StatusComponent.luau:351-371`): percorre a lista enquanto o `onFinish` a altera.
  Iterar sobre `table.clone(entry)` e zerar `group[name]` antes de encerrar os runners.
- F07 `RemoveStatusByID` (`StatusComponent.luau:454-465`): remove 2 instâncias. Tirar da lista primeiro
  e só então `runner:Stop(true)`, ou conferir que `list[i]` ainda é o runner.
- F08 `ClearAll`/`Destroy` (`StatusComponent.luau:776-796`): mesmo snapshot do F06.
- F09 `SkillRunner:ApplyStatus` (`sync/ServerScriptService/Modules/SkillRunner.luau:309-314`): usa a
  assinatura legada e o ID vira a tabela `opts`. Chamar `target.ApplyStatus(statusData, opts)`.
  Em `StatusComponent:_CreateRunner` (linha 254), `target.Entity` não existe num EntityCore: aceitar
  EntityCore como alvo.
- F39: recusar status em entidade com Health morta (ou flag explícita no status).
- Prova: BatchA T08 (auditoria 5/10 órfãos → 0), T09 (restaram ID1, ID4, ID5 → devem restar
  ID1, ID3, ID4, ID5), T10 (ID = "WantedID"), T46, T50 (0 órfãos).

### 3. Ciclo de vida das skills — F13, F14, F20, F54

- F14 (`SkillRunner.luau:161`): `onStart` sem proteção; erro escapa do SkillHandler e o runner fica
  registrado. `pcall` no `onStart`; em erro, `endSkill(true)` e o SkillHandler retorna false.
- F13 (`SkillRunner.luau:322-373`): erro no `onEnd` impede `RemoveActiveSkill`/`Unregister`/`onFinish`
  e cria runner fantasma (o próximo toque faz recast no runner morto). Proteger o `onEnd` e garantir
  a limpeza; no `SkillHandler` (`activate`, linhas 96-165) ignorar runners com `IsEnded()`.
- F54: `onEnd` roda depois do `onCancel` sem dizer o motivo. Passar `ctx.reason`
  (`"cancel" | "duration" | "stop"`) e revisar M1, Dash, Ultimate e WeaponTransform, que hoje
  repetem a limpeza em `onEnd` e `onCancel`.
- F20 (`HealthComponent.luau:171-187`): a morte não cancela skills (caster morto continua voando).
  Para não criar dependência Health → Combat (regra 20), prefira que o runner assine `IN.OnDeath`
  da própria entidade no `start()` (com `Own`) e se cancele.
- Prova: BatchB T20 (auditoria starts=1/recasts=1 → starts=2/recasts=0 e 0 ativos), T21 (sem erro
  escapando, 0 ativos), BatchU2 U3 (0 skills ativas e alvos soltos após a morte), Caps K1
  (recarga interrompida não recarrega).

### 4. Possessão — F02, F03, F04, F21, F22, F23, F24 (depois das decisões 4b e 4c)

- F02 (`sync/ServerScriptService/Scripts/Main.server.luau:29-40` + `ControlComponent.luau:109`):
  respawn durante possessão deixa o player sem entidade (`Release` dá erro no `SetNetworkOwner`
  da peça destruída e o `DataManager.Create` não roda). Só mexer em ownership de peça que está
  no workspace e não ancorada, e sempre terminar o Release (`SetNativeControlSuspended(false)`).
- F03 (`ControlComponent.luau:212-218`): possuído destruído deixa a rota no ID morto e o corpo
  server-owned. `Destroy` com controlador player chama `Release()`; o GlobalAntiCheat volta ao
  `NativeID` quando o ID roteado não existe mais.
- F04 (`ControlComponent.luau:76`): possuir algo estando numa entidade ancorada lança erro no meio.
  Validar `IsDescendantOf(workspace)`, `not Anchored` e `CanSetNetworkOwnership()` antes; só aplicar
  depois de validar tudo.
- F21 (`ControlComponent.luau:56-127`): aninhada deixa controladores velhos; implementar a semântica
  escolhida (pilha ou troca) e atualizar o `Controller` do corpo anterior.
- F22 (`sync/ServerScriptService/Modules/GlobalAntiCheat.luau:80-105`): o `suspendNative=true` é
  seguido de outra mensagem com `false`. Guardar o estado no `tracked` e mandar uma mensagem só.
- F23 (`ControlComponent.luau:65-77`): o corpo deixado anda sozinho com o último input. Zerar a
  `Direction` dele no Possess e a do possuído no Release.
- F24 (`ControlComponent.luau:56-94`): `Possess({AI = true, Brain = fn})` é ignorado. Trocar o Brain
  do AIComponent do alvo (guardando o anterior) e restaurar no Release.
- Prova: BatchP P1–P8, BatchU2 P4b, `probes/ManualPossessionSeq` + `client/__AuditDriver` (sem erro e
  rota final no corpo), `client/__AuditClientHooks` (uma mensagem com `suspendNative=true`).

### 5. F05 — autoridade de movimento (só depois da decisão 4a)

- Onde: `GlobalAntiCheat.luau:140-152` (checagens vazias), `sync/ServerScriptService/EntityData/Components/MovementComponent.luau:212-218`
  (ownership só para NPC), `sync/StarterPlayer/StarterPlayerScripts/CameraOverride.luau:232-238`
  (o lock é um pedido que o cliente obedece se quiser).
- Entregue antes um plano curto com o modelo escolhido e espere aprovação.
- Prova: `server/__AuditSec` + `client/__AuditExploiter` (auditoria: speed hack de 87 studs/s,
  teleporte de 150 studs e ~43 studs andados sob Stun e sob Lock, todos aceitos).

## Fora deste lote

Não corrija agora: dano e escudos (F10, F11), cooldown e loadout (F12, F16), hitbox (F26, F27),
forças e ambiente (F29–F33), Ultimate da Schema (F19), animação (F25). Isso é o lote P1.
Achou algo novo? Anote e reporte (regra 7) em vez de corrigir.

## Armadilhas do ambiente de teste

- `execute_luau` do MCP roda numa VM separada da do jogo. Para testar, injete um `Script` em
  ServerScriptService com `Source` e deixe ele rodar; não o destrua antes de terminar.
- O teclado virtual do Studio não chega ao jogo; use os drivers de `tools/audit_suite/client/`.
- O `GrandIntegrationDemo` possui o player aos 5 s e ocupa a origem; teste a 800+ studs.

## Como reportar

Por item: arquivo:linha alterado, teste rodado e o número antes → depois. Bug novo com o mesmo
nível de detalhe das regras (arquivo, comportamento exato, por que acontece). Nome duplicado ou
com caixa diferente (regra 19), mesmo fora do escopo. Combine com o usuário o prefixo de debug
(regra 18) antes do primeiro `warn` novo.

# Handoff — F05: autoridade de movimento (validação e correção no servidor)

Você vai implementar o F05 da auditoria pelo **modelo B**, aprovado pelo usuário em 16/10/2026: o corpo do
player continua simulado pelo cliente, e o servidor valida e corrige. O Server Authority nativo do Roblox
(modelo A) fica para a reescrita do movimento. Trabalhe um passo por vez, prove cada um com teste e reporte
em português, de forma direta, com números antes → depois. O usuário quer críticas, não elogios.

## Estado em 16/10/2026: aplicado

Um commit por item: F29 `b5dc520`, F30 `4ecd4c5`, F76 `fd93280`, F46 `6a246f1` (D6 = aditiva, decisão do
usuário), F92 `efac924`, o validador do F05 `fc4c75a` e a janela por ping no commit seguinte. O resto deste
arquivo é o plano original.

| Prova | Antes → depois |
| --- | --- |
| S1 speed hack (~120 studs/s por 1 s) | 87 → 34 studs (1 correção) |
| S2 teleporte de 150 studs | aceito → revertido |
| S3 / S4 andar sob Stun / Lock | 43 / 43 → 5,6 / 4,7 studs |
| S5 a S8 | WalkSpeed do servidor fica 20; fuzz e spam sem erro; ventilador com 0 correções |
| Falsos positivos | 0 correções: andar, pular, queda de 60, Dash ×3, voo da Ultimate (90 studs/s), tether a 60 studs/s, ventilador 35000 parado e contra, Stun e Lock no meio da caminhada, possessão e volta, respawn, `GrandIntegrationDemo` |
| Regressão | BatchA 11/22, BatchB 5/12, BatchP 7/8, U2 com U2 e U3, IntegrationTests 7/7, `ManualPossessionSeq` inteira; Env 7/13 → 9/13 |

Desvios do plano, com o motivo:

- **Balde de crédito no lugar do balde com piso 0.** O plano zerava o `Excess` a cada correção (o cheater
  ganharia 4 studs por ciclo) e não guardava crédito para a rajada de replicação (player com lag levaria
  correção). Agora o crédito enche na velocidade permitida até `Movement_Burst_Seconds` dela, o movimento
  aceito o gasta e a dívida nunca é perdoada. `DECAY` e `TELEPORT_LIMIT` saíram; entraram
  `Movement_Burst_Seconds` (0,25) e `Movement_Latency_Window` (0,35), que segura o teto de uma Force por
  um tempo depois de ela acabar no servidor.
- **S1 ficou em 34 studs, acima dos ≤ 29 estimados.** A diferença é o crédito de rajada (0,25 s ≈ 6,75 studs).
  Baixar `Movement_Burst_Seconds` aperta, ao custo de tolerar menos lag, e lag real não dá para medir no Studio.
- **Confiança automática, sem `TrustPosition`.** A hipótese se provou: no servidor, o CFrame-changed da raiz deu
  0 disparos para a física do cliente e para CFrame forçado no cliente, e 1 por escrita do servidor (3 escritas
  no mesmo frame = 3 disparos). A correção do próprio validador é descontada (`SelfWrites`).
- **F92 corrigido junto**: o cliente não parava o corpo no Lock, falso positivo garantido.
- **Janelas por ping.** Com 200 ms de atraso simulado (`settings().Network.IncomingReplicationLag = 0.2`),
  andar e pular passaram, mas Dash ×3 (2 correções), voo da Ultimate (1) e Stun/Lock no meio da caminhada
  (2) não: o fim da Force ou do Stun chega ao cliente e volta ao servidor depois que a janela de 0,35 s
  fechou. As janelas de latência e de confiança agora somam `Movement_Ping_Factor` (2) × `GetNetworkPing`.
  No Studio o `GetNetworkPing` dá 0 com o atraso simulado, então a prova foi com o ping emulado (+0,4 s nas
  janelas): 0 correções nesses cenários, e S1 a S4 com lag ficaram iguais (S1 26 → 24,6; S3 5,8 → 4,9).
  Falta conferir no servidor publicado se o `GetNetworkPing` é ida-e-volta ou um sentido.

Limitações anotadas (fora de escopo): noclip; subida contínua até a velocidade de pulo (voo); compensação de
latência; empurrão físico fora das Forces (colisão com NPC, Explosion); veículos (sentado não é validado);
NPC com Humanoid segue lento (F31); no vento, a parte da caminhada do player segue o input que chegou ao
servidor (~1 RTT, consequência do D6). Para o modelo A, desligue `Movement_Validation_Enabled` em `Settings`.

## Contexto em 1 minuto

- Repo Roblox/Luau. `sync/` é o **Script Sync nativo do Studio, bidirecional** (place UNTOLD BATTLEGROUNDS,
  placeId 114873614457629). Um `.luau` editado no disco chega ao Studio em ~2 s; o `multi_edit` do MCP
  também funciona, mas só em modo Edit. Depois de editar, confira que Studio = disco por hash (FNV-1a do
  `Source` sem `\r`).
- Regras do framework: leia `.agents/rules/00` a `03`. Pesam aqui: 1 (DRY), 7 (um módulo por vez),
  12 (nada de valor solto: limites vão para `Physics/Settings.luau`), 16/20 (dependência entre componentes
  explícita ou eliminada), 17 (formato com dono único), 18 (nada de print de debug; warn estrutural com
  prefixo `[Modulo]`, como o resto do código).
- Auditoria: `tools/audit_suite/AUDITORIA.md` (F01–F91; F75 em diante são de 16/10). Suíte e como rodar:
  `tools/audit_suite/README.md`. Estado do lote P0: `HANDOFF_P0.md`.

## Antes de qualquer git

- Os itens 1 a 4 do P0 estão aplicados no Studio e no disco, **sem commit**. Não restaure nem descarte nada.
- Ruído do sync que não é seu: ~80 `.luau` só com fim de linha, `sourcemap.json` e
  `sync/ReplicatedStorage/Assets/Weapons/Schema/Martelo/WeaponData__14070.luau` (a pasta `Martelo` duplicada
  no Studio, F18). Não commite nem apague isso sem perguntar.
- Sem commit/push até o usuário pedir.

## Decisões já tomadas (não reabrir)

- F05: modelo B agora; Server Authority nativo (`Workspace.AuthorityMode = Server`, lançado em 09/07/2026)
  depois, como alvo da reescrita do movimento.
- HP 0: o framework **não** mata o Humanoid nem força respawn, de propósito. O que acontece com HP 0 é do
  dev final. O validador não presume nada sobre morte.
- Controle: pilha por player, configurável (`Policy` Stack/Swap, `PauseAI`, `ReleaseOnDeath`). Durante a
  possessão o corpo nativo do player fica server-owned e é dirigido pelo servidor.

## O que mudou no P0 e você vai encontrar

| Onde | API nova ou alterada |
| --- | --- |
| `StateTable` / `Helper` | `StateTable.RunInChain(label, subject, fn, ...)`: dono único do disjuntor de recursão; `TakeDamage` e `ApplyStatus` passam por ele |
| `StateTable/Enum` | `Enum.EndReasons` (`cancel`, `duration`, `stop`), `Enum.EnginePriority` (listeners internos do motor) e `Enum.DeathDefaults` (regras de morte do motor, padrão ligado: `CancelSkillsOnDeath`, `RefuseStatusOnDeath`; override por entidade no config do componente, resolvido uma vez no `new()` por `StateTable.ResolveDeathPolicy`) |
| `SkillRunner` | `start()` devolve `false` se o `onStart` falhou; `onCancel`/`onEnd` recebem `ctx.reason`; erro em callback vira warn e nunca interrompe a limpeza; `Own()` depois do fim roda na hora |
| `CombatComponent` | `StopAllActiveSkills(cancel, runnerType?)` com snapshot; a morte (`IN.OnDeath`) cancela as skills ativas, salvo `CancelSkillsOnDeath = false` no config (aí nem assina) |
| `StatusComponent` | `RemoveStatus` devolve boolean; status recusado em entidade morta, salvo `RefuseStatusOnDeath = false` no config ou `data.allowOnDead` no status |
| `ControlComponent` | `Possess(controller, opts)`, `Policy`, `ReleasePlayer(player, leaving?)`, `GetPossessionOf(player)` = topo da pilha; `handBody(core, toPlayer)` é o único lugar que troca o dono de um corpo |
| `GlobalAntiCheat` | `SetControlledEntity(player, id, suspendNative?)` manda **uma** mensagem com o estado completo; `GetNativeEntityId(player)`; `PriorControlledID` saiu (a pilha mora no ControlComponent) |
| `AIComponent` | `GetBrain()`, `IsAIEnabled()` |

## Passo 0 — forças (pré-requisito técnico)

O validador soma a velocidade das Forces ativas ao limite permitido. Hoje isso está errado de duas formas:

- **F29**: cada poll de área (10 Hz) cria uma força nova de 0,5 s, e ficam até 5 ativas somando velocidade.
  Um ventilador de 30 studs/s vira um teto de 150, ou seja, folga de 5× para um speed hack dentro do vento.
- **F76**: o `MaxForce` de força Soft é ignorado (`MovementController.luau:211` calcula, `:248` sempre usa
  `Soft_Force_Strength` = 2500). Medido em 16/10, ventilador de 30 studs/s no player parado no chão:
  1,4 stud em 1,5 s (no ar, 27 studs/s). Com o teto em 35000 por experimento, o player foi a 149 studs/s,
  por causa do F29.

O que fazer:

1. F29: `AreaBehaviors.DirectionalForce` renova a mesma força (uma por entidade e tipo) em vez de criar outra
   a cada `OnStay`.
2. F76: orçamento por eixo Soft = maior `MaxForce` entre as Soft que reivindicam o eixo (padrão
   `Soft_Force_Strength`).
3. F30: força de ambiente com `RequiresControl = false` por padrão.

Prova: `probes/WindAccumulation` (antes: pico de 5 forças e 100 studs/s; esperado: 1 força, ~20 studs/s) e o
ventilador no player parado no chão. Não faça agora o F32/F33/F46 (força por massa, somada à caminhada): é P1.

O usuário aprovou seguir com o anticheat, e este passo foi recomendado junto. Se ele não confirmar o Passo 0
explicitamente, pergunte antes de mexer nas forças.

## Passo 1 — validador no `GlobalAntiCheat`

`_Update` já está conectado ao Heartbeat e vazio; `CheckPosition` e `CheckNoClip` estão vazios;
`tracked.LastPosition` existe e não é usado.

- **Quem é validado:** players em `TrackedPlayers` cujo corpo nativo (`NativeID`) tem a raiz com
  `GetNetworkOwner() == player`. Corpo server-owned (possessão) fica de fora: o servidor já manda nele.
- **Estado novo em `tracked`** (dono do formato: o `Register`): `LastValid` (Vector3), `Excess` (studs) e o
  que for preciso para confiar em movimento feito pelo servidor.
- **A cada Heartbeat (dt):**
  1. `delta = root.Position - LastValid`; horizontal = módulo em XZ; vertical = `delta.Y`.
  2. Limite horizontal = (`WalkSpeed` do servidor × tolerância + velocidade horizontal das Forces + velocidade
     horizontal do chão + folga) × dt.
     - `WalkSpeed`: o do Humanoid **no servidor**, que o `MovementController` seta todo frame (`GetSpeed`, ou
       0 com `canMove = false`). O cliente muda o dele, mas isso não replica. O Lock (`tracked.Locked`) não
       zera o `WalkSpeed`: zere a parcela de caminhada no validador.
     - Forces: não leia `ActiveForces` de fora (regra 17). Exponha no `MovementComponent` um getter do
       orçamento de velocidade (`Speed` número ou função `(elapsed, duration)`; tether usa `FollowMaxSpeed`).
     - Chão: um raycast curto para baixo; se a peça tem `AssemblyLinearVelocity` (plataforma móvel), some.
  3. Vertical: cair é livre; subir até a velocidade de pulo (`sqrt(2 * workspace.Gravity * JumpHeight)`) + Y
     das Forces + Y do chão + folga.
  4. Balde com vazamento: `Excess = max(0, Excess + excessoDoFrame - DECAY * dt)`. Corrija quando
     `Excess > EXCESS_LIMIT` ou quando um frame sozinho passa de `TELEPORT_LIMIT`.
  5. Correção: `root.CFrame = CFrame.new(LastValid) * rotação atual`, `root.AssemblyLinearVelocity = zero`,
     `Excess = 0`, e um warn `[AntiCheat]` com no máximo 1 por segundo por player.
  6. Sem violação: `LastValid = root.Position`.
- **Movimento feito pelo servidor não pode virar correção** (`PivotTo` de teste, `Teleport`, respawn, fim
  da possessão):
  - Hipótese, prove antes de usar: no servidor, `root:GetPropertyChangedSignal("CFrame")` dispara para
    escrita de script e não para a física replicada do cliente. Teste: o `__AuditExploiter` move o HRP por
    CFrame no cliente; conte os disparos no servidor nos dois casos.
  - Se a hipótese falhar, use uma API explícita (`AntiCheat.TrustPosition(player)`) chamada pelo
    `CharacterComponent:Teleport`, pelo `handBody` do ControlComponent na volta ao player e pelo `Register`.
  - Em qualquer caso, o `Register` e a volta do corpo ao player resetam `LastValid`.
- **Limites iniciais** (bloco novo em `Physics/Settings.luau`): tolerância 1,25; folga 2 studs/s;
  `EXCESS_LIMIT` 4 studs; `DECAY` 4 studs/s; `TELEPORT_LIMIT` 12 studs por frame. Calibre com jogo normal:
  zero correções esperadas.
- **Custo:** O(players) por frame e um raycast por player. Se pesar, amostre a 20 Hz.
- **Fora de escopo agora:** noclip (`CheckNoClip`), voo parado no ar, compensação de latência. Anote, não
  implemente.

## Prova

1. `server/__AuditSec` + `client/__AuditExploiter` (o exploiter vai como LocalScript no PlayerGui). Na
   auditoria: S1 speed hack de 87 studs em 1 s aceito, S2 teleporte de 150 studs aceito, S3 e S4 com ~43
   studs andados sob Stun e sob Lock. Esperado: S1 ≤ WalkSpeed × 1,25 + 4 studs; S2 revertido (2 s depois
   não está lá); S3 e S4 ≤ 4 studs; S5 com o `WalkSpeed` do servidor inalterado; S6 e S7 sem erro novo;
   S8 (ventilador) **sem** correção.
2. Falsos positivos, zero correções: andar e pular normal; cair de 60 studs; Dash da Schema (80 studs/s);
   voo da Ultimate (90 studs/s); ser agarrado pela Ultimate de um NPC (tether); ventilador; respawn;
   possessão e volta.
3. Regressão, nada pode piorar. Números de 16/10: BatchA 11/22, BatchB 5/12, BatchP 7/8, IntegrationTests 7/7,
   U2 com U2 e U3 passando, sonda `ManualPossessionSeq` inteira.

Para simular input real do cliente (o teclado virtual do Studio é recusado), num LocalScript:

```lua
local Controls = require(player.PlayerScripts.PlayerModule):GetControls()
local kb = Controls.activeController
kb.forwardValue = -1; kb:UpdateMovement(Enum.UserInputState.Begin) -- W segurado
kb.jumpRequested = true; kb:UpdateJump()                             -- pulo
```

O ControlModule usa isso como usaria a tecla, e o InputService envia o `RequestDir` real.

## Armadilhas do ambiente

- Teste roda no Play: crie um `Script` com `Source` e parent em ServerScriptService pelo `execute_luau`
  (datamodel Server); o `execute_luau` sozinho roda numa VM separada e enxerga outro `DataManager`.
  Compare o hash do `Source` injetado com o do arquivo para descartar erro de transcrição.
- `multi_edit` falha no Play ("Edit datamodel is not available in Play mode"): pare o Play antes de editar.
- O GrandIntegrationDemo possui o player aos 5 s por 30 s: rode teste de player com t > 36 s e em zonas a
  800+ studs.
- `workspace.Rig` é ancorado: entidade criada dele não anda (F50). Desancore os parts quando o teste precisa
  de movimento (como a U2 faz).
- Carga do Studio: em 16/10 ele usava 14 a 18 núcleos parado, e os tempos de frame (T16, T17) não eram
  comparáveis com a auditoria. Para comparar desempenho, meça CPU com `os.clock()`.
- Não edite o mesmo arquivo pelo disco e pelo Studio ao mesmo tempo.

## Depois (modelo A), não faça agora

Mantenha o validador isolado no AntiCheat e desligável por um flag em `Settings`: com `AuthorityMode = Server`
ele fica redundante. A migração exige `SignalBehavior` Deferred no jogo todo, InputActions no lugar do
InputService e o movimento em `BindToSimulation`, compartilhado com o cliente.

## Como reportar

Por passo: arquivo:linha alterado, teste rodado e o número antes → depois. Achado novo vai para
`AUDITORIA.md` (seção "Achados novos"), no mesmo formato: onde, comportamento exato, evidência e correção.
Nome duplicado ou com caixa diferente (regra 19) também, mesmo fora do escopo.

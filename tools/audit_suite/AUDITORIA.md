# Framework de Combate — Auditoria de Falhas e Brechas

> Cópia em Markdown do doc da auditoria de 15/10/2026. A versão viva (com comentários e o gráfico) está no [doc online](https://claude.ai/code/artifact/46b99f1b-a621-440c-a492-107e7e5c1e9f).

Oct 15, 2026 · @Gabi

## Resumo executivo

O framework aguenta carga e luta longa sem quebrar, mas ainda não é desacoplado, abstrato nem server-authoritative. Dos 99 testes, 65 falharam, e confirmei 74 falhas: 5 críticas e 26 altas. O Place está igual ao GitHub (159 de 161 scripts idênticos); a exceção é a pasta `Martelo` duplicada.

**Maiores riscos**

1. Qualquer erro dentro da cadeia de dano consome o `MAX_RECURSION` global. Depois de 50 erros, o servidor inteiro para de aplicar dano e status (F01).
2. O movimento do player é do cliente. Speed hack (87 studs/s), teleporte de 150 studs e andar sob Stun ou Lock foram aceitos sem correção (F05).
3. A possessão deixa o player sem corpo ou sem controle. Isso acontece no respawn durante a possessão, quando o possuído é destruído, na troca a partir de entidade ancorada e na possessão aninhada (F02 a F04, F21). IA possuindo IA não funciona (F24).
4. Status e skills deixam estado fantasma. Remover stacks deixa metade dos runners rodando, um erro em `onStart`/`onEnd` deixa runner preso, e o recast é bloqueado pelo próprio cooldown (F06 a F15).
5. Há assunções de jogo embutidas: 6 intents fixas, kit preso ao `CharacterDatabase`, assets pelo nome do personagem, nada de time, recurso ou alvo, e forças que ignoram a massa (vento não move o chefe nem o player).

**O que se mostrou sólido:** o TriggerSet passou em todos os testes de semântica, o `GestureResolver` passou no fuzz, o disjuntor síncrono para a recursão em 50, e a arena de 5 min com 32 entidades terminou com 0 erros do motor e limpeza total, e o soak de 15 min também passou sem nenhum erro. Dos 13 kits hipotéticos, 13 rodaram só com a API pública, mas com 17 workarounds diferentes.

## Sincronização Place ↔ GitHub

O código do Place está sincronizado: 159 de 161 scripts do Studio são idênticos byte a byte ao `origin/main` (commit `1b56ea4`, 25/09/2026). A única divergência é uma pasta de arma duplicada, que o GitHub não consegue representar.

| Comparação | Método | Resultado |
| --- | --- | --- |
| `main` local × `origin/main` | `git fetch` + `rev-parse` | Idênticos, nada para push ou pull |
| Studio × GitHub | Hash FNV-1a do `Source` (sem `\r`) de 161 scripts, comparado ao `git show HEAD:` | 159 idênticos, 0 com conteúdo diferente, 2 sem par |
| Editor do Studio × `Source` | `ScriptEditorService:GetEditorSource` | Nenhum rascunho não salvo |
| Working tree local | `git diff --ignore-all-space` | 82 `.luau` marcados só por fim de linha (LF × `autocrlf=true`), `sourcemap.json` regenerado, 1 arquivo apagado |

**Divergências encontradas**

1. `ReplicatedStorage.Assets.Weapons.Schema` tem **duas pastas `Martelo`**, com o mesmo nome e a mesma capitalização. A primeira está completa: `WeaponData` de 1006 bytes, idêntico ao `martelo/WeaponData.luau` do GitHub, mais o Model com hitbox (128 `DmgPoint`). A segunda é legada: só um `WeaponData` com `BaseName = "HunterBlades"` (467 bytes), sem `Loadout`, e não existe no GitHub.
2. O `WeaponComponent` resolve a arma por `FindFirstChild` (linhas 68 e 212), então a pasta carregada depende da ordem dos filhos. Isso viola a regra 19. O bug 8 do `.agents` (`martelo` × `Martelo`) virou duplicata exata em vez de ser resolvido.
3. O sync mapeou as duas pastas para `Martelo/WeaponData.luau` e `Martelo/WeaponData__14070.luau`. No Windows (case-insensitive), ele apagou o `martelo/WeaponData.luau` e não escreveu nenhum dos dois. **Se o working tree for commitado agora, o GitHub perde o WeaponData do Martelo.**
4. `Workspace.martelo` (Model, minúsculo) é uma terceira variante de nome do mesmo asset.
5. `.agents/rules/*` e `sprints.md` estão commitados, mas o `02-bugs-e-objetivos.md` pede que fiquem no `.gitignore`, e o repositório não tem `.gitignore`.

**Para fechar:** apague a segunda pasta `Martelo` no Studio e resolva o `Workspace.martelo`. Depois deixe o sync reescrever `Martelo/WeaponData.luau`, confira o `git diff` e commite. Antes disso, descarte o ruído de fim de linha (`git add --renormalize .`, ou um `.gitattributes` com `*.luau text eol=lf`).

## Arquitetura confirmada

O código bate com a arquitetura descrita em `.agents/rules`: ECS com API injetada, runtime de skills único, pub/sub IN/OUT e física por constraints. A exceção é a autoridade. O combate é decidido no servidor, mas a posição e a velocidade do próprio personagem continuam com o cliente.

> Diagrama das 5 camadas (cliente, borda de rede, entidade, runtime e combate, mundo) disponível no [doc online](https://claude.ai/code/artifact/46b99f1b-a621-440c-a492-107e7e5c1e9f).

O input desce pelas camadas até o mundo. A falha de autoridade está no topo: o WASD nativo move o corpo do player sem passar pela borda de rede.

| Camada | Módulos | Papel | Desvio encontrado |
| --- | --- | --- | --- |
| Input (cliente) | `InputService`, `InputConfig`, fork do `ControlModule`, `LookDirectionBroadcaster`, `CameraOverride` | Tecla vira Intent; envia Press/Release, direção (20 Hz) e mira (30 Hz) | Só 6 intents fixas no `Intents.luau` |
| Borda de rede | `InputValidator`, `GestureResolver`, `InputSessions`, `GlobalAntiCheat` | Valida tipo, faixa e taxa; resolve Tap/Hold/DoubleTap; roteia player para entidade | `CheckPosition`, `CheckNoClip` e `_Update` vazios |
| Entidades | `DataManager`, `EntityCore`, `ComponentUtils`, `EntityWrapper` | Registro por ID, auto-registro de componentes, API injetada, stubs compartilhados | API não sai da entidade no `RemoveComponent` |
| Componentes | Character, Movement, Combat, Status, Health, Weapon, Attributes, Animation, Control, AI | Estado por entidade | Só Animation declara `Requires`; Movement, Weapon e Combat dependem sem declarar |
| Runtime de skills | `SkillFactory`, `SkillRunner`, `SkillScheduler`, `SkillHandler` | Ciclo Idle, Casting, Running, Ended num único Heartbeat (status a cada 2 frames) | `onStart` e `onEnd` sem isolamento de erro |
| Dados de combate | `StateTable` (Enum, States, Status, ActionStates), `Helper.BuildContext`, `Lineage`, `TraitQuery` | Tags, traits, imunidades, contexto de dano, trilha de origem | Dois formatos diferentes chamados "Context" |
| Pub/sub | `TriggerSet` | Breakpoints IN/OUT com Priority, Limit, TTD e herança por Fork | Owner é string global |
| Física | `MovementController`, `ForceRig`, `Physics/Settings` | Forças Hard/Soft por eixo, tether, gravidade por atributo | Players continuam client-owned |
| Hitbox | `HitboxWrapper` (arma, pool global), `HitboxSpawner`/`Behaviors`/`Presets`, `ShapecastHitbox` | Sweep por `DmgPoint`, projéteis desacoplados | Detalhado na seção de falhas |
| Apresentação | `VFXManager`/`VFXPlayer`, `SoundManager`, `UpdateHealthBar`, `SkillFired` | Efeitos, som e UI | Canal fixo: só HP e cooldown chegam ao cliente |
| Conteúdo | `CharacterDatabase`, `SkillDatabase`, `Assets.Weapons`, `AnimationLib`, `MinionFactory` | Dados por personagem e forma | Armas e animações indexadas pelo nome do personagem |

**Onde o servidor manda de fato:** HP, dano, status, cooldown, detecção de hit, criação das forças e ownership dos NPCs (`SetNetworkOwner(nil)` em força Hard).

**Onde o cliente manda:** posição e velocidade do próprio corpo (network owner padrão do Roblox) e a andada por WASD (o `ControlModule` nativo chama `Player:Move`). O lock é um pedido: o servidor envia `ControlStateChanged` e o próprio cliente desliga o `moveFunction`. O servidor zera `WalkSpeed` em Stun/Root, mas não confere a posição que volta.

**Pontos fortes reais:** o disjuntor de recursão síncrona funciona (ping-pong de reflexo para em 50), o TriggerSet isola erro de listener com `xpcall` e passou em todos os testes de semântica, e o `GestureResolver` passou no fuzz sem violar a invariante Activate/Release.

## Bateria de testes

Foram 99 testes em 9 baterias, mais 5 min de arena todos-contra-todos, um soak de 15 min e testes manuais. 65 testes falharam. O motor raramente quebra (0 erros dele em 5 min de arena), mas muitas mecânicas se comportam diferente do contrato.

| Bateria | Falharam / total | % |
| --- | --- | --- |
| Possessão e controle | 8 / 9 | 89% |
| Núcleo, status e dano | 17 / 22 | 77% |
| Scheduler, skills e pub/sub | 9 / 12 | 75% |
| Hitbox, arma, animação, física | 9 / 12 | 75% |
| Ultimate da Schema | 3 / 4 | 75% |
| Segurança (cliente malicioso) | 5 / 7 | 71% |
| Ambiente | 9 / 15 | 60% |
| Kits hipotéticos | 4 / 11 | 36% |
| Suíte original do repo | 1 / 7 | 14% |
| **Total** | **65 / 99** | **66%** |

A possessão falhou em 8 de 9 testes e o núcleo em 17 de 22. Os kits falharam menos porque contornam as lacunas com workarounds.

**Como foi rodado**

- Tudo no Play do Studio, com Scripts injetados em runtime na VM do jogo. O `execute_luau` roda numa VM separada e enxerga outro `DataManager`, por isso os testes rodam dentro do jogo.
- Zonas isoladas a mais de 800 studs dos demos, com plataformas próprias e limpeza no fim de cada teste. A profundidade de cadeia (`MAX_RECURSION`) foi restaurada logo após cada medição de vazamento.
- Os testes do lado do cliente usam um LocalScript no `PlayerGui`, que é exatamente o que um exploiter consegue rodar.
- Nos testes manuais o clique do mouse chega ao jogo, mas o teclado virtual do Studio é recusado. Por isso os movimentos manuais foram enviados pelos mesmos remotes do `InputService` (`RequestDir`, `RequestIntent`).
- As 12 baterias foram salvas como arquivos `.luau` reaproveitáveis (pasta `audit_suite`). Podem entrar no repo para rerodar depois das correções.

| Bateria | O que cobre | Método |
| --- | --- | --- |
| Suíte original | Os 7 testes de `IntegrationTests` | Rodou sozinha no Play |
| Núcleo, status e dano | Criar e destruir 300 entidades, API após `RemoveComponent`, stacks, IDs, escudos, block, iFrame, cadeia de recursão | 22 testes automáticos |
| Scheduler, skills e pub/sub | 3000 runners simultâneos, recast, maxInstances, erros em callbacks, cadeia assíncrona, 3000 listeners, fuzz do `GestureResolver` | 12 testes, fuzz de 8 s |
| Hitbox, arma, animação, física | Timer, sweep do Blockcast, giro de arma, Martelo real, WeaponTransform, tracks, direções, 350 forças, atributos, ownership | 12 testes |
| Possessão e controle | Player possui NPC, aninhada, alvo destruído, IA possui IA, Lock, HUD, câmera, respawn | 9 testes com o player real |
| Ultimate da Schema | Voo com 3 alvos, curva de 90°, cancel, fim natural, morte do caster, ult usada pelo player | 4 testes |
| Kits hipotéticos | 8 personagens e 5 inimigos feitos só com a API pública | 11 cenários determinísticos |
| Ambiente | Ventilador, zonas sobrepostas, Root no vento, gravidade, slow/speed, esteira, knockback, jump pad, 20 ventiladores, dash e tether no vento | 15 testes |
| Segurança | Speed hack, teleporte, andar com Stun e Lock, fuzz de remotes, spam de 7.300 mensagens, forças no player | 7 testes via cliente |

**Arena (5 min, todos contra todos):** 12 kits mais um enxame de 20, com respawn e 4 possessões IA × IA. O motor teve 0 erros e a limpeza final deixou 0 runners, 0 projéteis e cadeia em 0. O frame médio foi de 21 ms, com pico de 147 ms. Houve 2.340 warnings e até 3 entidades mortas com skill ainda rodando.

**Soak (15 min, mesma arena):** o motor teve 0 erros em 177 amostras. A memória oscilou entre 5,2 e 9,5 MB, com leve alta entre o primeiro e o último terço (7,0 → 7,9 MB) e 6,4 MB depois da limpeza. O frame médio foi de 26,7 ms, com pico de 172 ms. Foram 5.596 warnings (cerca de 6 por segundo) e até 2 entidades mortas com skill rodando. Restaram 2 runners depois da limpeza, que podem ser do GrandIntegrationDemo, que continua ativo no Play.

**Testes manuais:** M1 pelo mouse, possessão do chefe (câmera, HUD, ataque pelo M1), possessão da torre e do enxame pela rede, troca aninhada torre → enxame, e a Ultimate do player contra NPCs.

## Falhas encontradas

Foram 74 falhas confirmadas: 5 críticas, 26 altas, 32 médias e 11 baixas. Todas têm teste ou leitura de código como evidência. As críticas derrubam o dano do servidor inteiro, deixam o player sem corpo ou permitem trapaça de movimento.

**Ultimate da Schema (pedido específico).** Ela agarra, mas não segura. Com caster NPC a 88 studs/s, o alvo fica até 10 studs atrás do ponto de grab. Com o player voando a 82 studs/s, só 2 de 3 alvos foram agarrados e o erro chegou a 16,9 studs. As causas:

1. O tether só tem controle proporcional (`toDesired × 16`, sem somar a velocidade do caster), e o `FollowMaxSpeed` é igual à velocidade de voo, então o alvo nunca alcança.
2. Todo alvo vai para o mesmo offset `(0, 0, -4)`: os 3 alvos ficaram a 0,6 stud uns dos outros, colidindo.
3. O grab não pertence ao runner. Cancelar não solta (3 de 3 presos 1 s depois, um arrastado 90 studs), e a duração é de 20 s contados do hit.
4. A morte do caster não encerra a skill: o caster morto continuou voando e segurando 3 alvos.
5. Em vítima player, o `AddForce` não pega ownership, então o tether é simulado pelo cliente da vítima.

Para corrigir: guardar os IDs dos grabs no runner e soltá-los com `self:Own(...)`, usar a duração restante, somar a velocidade do alvo-âncora no `FollowTarget`, dar offset por índice com CollisionGroup sem colisão entre agarrados, e cancelar as skills ativas no `Die`.

| # | Sev. | Onde | O que acontece | Evidência | Correção |
| --- | --- | --- | --- | --- | --- |
| F01 | Crítica | `StateTable/Helper.luau:46-58`, `HealthComponent.luau:78-86`, `StatusComponent.luau:106-114` | Erro dentro de `TakeDamage`/`ApplyStatus` nunca chama `ExitChain`. Depois de 50 erros, todo dano e todo status do servidor são recusados com `MaxRecursion` | T14: 10 de 10 vazaram; entidade saudável recebeu `false/MaxRecursion` | Executar o miolo em `pcall` e sempre sair da cadeia; profundidade por contexto em vez de global |
| F02 | Crítica | `Main.server.luau:30-33`, `ControlComponent.luau:109` | Respawn durante possessão: `Release` dá erro no `SetNetworkOwner` da peça destruída e o `DataManager.Create` do corpo novo não roda. O player fica sem entidade | P8: entidade apontando para model com `Parent=nil` | Criar o corpo antes de soltar; checar `IsDescendantOf(workspace)` antes do ownership |
| F03 | Crítica | `ControlComponent.luau:212-218` | Possuído destruído ou morto: o input continua roteado para o ID morto, e o corpo do player fica server-owned com `DrivesInput=true` | P3; reproduzido 2 vezes na arena | `Destroy` chama `Release`; o AntiCheat volta ao corpo nativo quando o ID some |
| F04 | Crítica | `ControlComponent.luau:76` | Possuir algo enquanto possui uma entidade com raiz ancorada (torre) lança erro no meio do `Possess`. A rota fica presa na torre | Teste manual torre → enxame | Checar `Anchored`/`CanSetNetworkOwnership()` antes; transação com rollback |
| F05 | Crítica | `GlobalAntiCheat.luau:140-152`, `MovementComponent.luau:212-218` | Movimento do player é do cliente: speed hack por CFrame (87 studs em 1 s), teleporte de 150 studs, andar com Stun (43 studs) e com Lock (43 studs), tudo aceito | S1 a S4 | **Corrigido em 16/10** (modelo B, decisão do usuário): validador no `GlobalAntiCheat` (crédito de velocidade sobre WalkSpeed do servidor + Forces + chão; correção para a última posição aceita; movimento feito pelo servidor é confiável). Medido: S1 87 → 34 studs; S2 revertido; S3 43 → 5,6; S4 43 → 4,7; 0 correções em jogo legítimo (andar, pular, queda de 60, Dash, voo da Ultimate, tether, ventilador, possessão, respawn, `GrandIntegrationDemo`). Com 200 ms de atraso simulado, Dash, voo e Stun/Lock davam correção falsa; as janelas passaram a somar 2 × `GetNetworkPing` (0 correções com o ping emulado, segurança igual). Server Authority nativo fica para a reescrita do movimento |
| F06 | Alta | `StatusComponent.luau:351-371` | `RemoveStatus` em stack de instâncias percorre a lista enquanto o `onFinish` a altera. Metade dos runners fica órfã, rodando invisível | T08: 5 de 10 continuaram no `onStep` | Iterar sobre um snapshot e limpar a lista antes de encerrar |
| F07 | Alta | `StatusComponent.luau:454-465` | `RemoveStatusByID` remove 2 instâncias: o `onFinish` já tirou o runner e o `table.remove(list, i)` tira a próxima | T09: removeu ID2 e ID3 | Remover só se `list[i]` ainda for o runner |
| F08 | Alta | `StatusComponent.luau:790-796`, `StatusComponent.luau:351-371` | Entidade destruída com stack múltipla deixa runners vivos | T50: 5 de 10 rodando após a remoção | Mesmo snapshot de F06 no `ClearAll` |
| F09 | Alta | `SkillRunner.luau:309-314` | `SkillRunner:ApplyStatus` passa `opts` como ID (assinatura legada). O ID vira uma tabela, `opts.ID` é ignorado e `RemoveStatusByID(string)` falha | T10 | Chamar `target.ApplyStatus(statusData, opts)` |
| F10 | Alta | `StatusComponent.luau:648`, `StatusComponent.luau:664` | `ApplyMitigation` lê `blockRunner.data.traits` em vez de `.data.data.traits`: Unbreakable e TrueBlock nunca valem | T12; K3 (QuebraGuarda quebrou bloqueio Unbreakable) | Ler as traits do meta (`entry.data.data`) via `StateTable.HasTrait` |
| F11 | Alta | `SkillRunner.luau:247-262`, `Helper.luau:147-151` | `ShieldsFrom` sem `onTrigger` não bloqueia nada. Além disso, `CheckBlockFilter` recebe o runner e lê `runner.data.data` (nil), então pula o filtro | T11: StatusShield não barrou DOT | Escudo bloqueia por padrão; `onTrigger` só para customizar; filtro lendo o meta certo |
| F12 | Alta | `SkillHandler.luau:105` e `SkillHandler.luau:126-134` | O cooldown é checado antes do recast: o `onRecast` nunca roda enquanto o cooldown da própria skill corre | T18 | Checar recast antes do cooldown, ou usar política de cooldown configurável |
| F13 | Alta | `SkillRunner.luau:355` | Erro no `onEnd` deixa o runner "fantasma" em `ActiveSkills`, e o próximo toque faz recast no runner morto | T20: starts=1, recasts=1 | `pcall` no `onEnd` e limpeza garantida; ignorar runners `Ended` no SkillHandler |
| F14 | Alta | `SkillRunner.luau:161` | Erro no `onStart` escapa do SkillHandler e deixa o runner registrado, com estado parcial (status aplicado) | T21 | `pcall` no `onStart`; em erro, `endSkill(true)` |
| F15 | Alta | `SkillScheduler.luau:29-44`, `SkillScheduler.luau:65-79` | Encerrar um runner de índice menor durante o update desloca a lista e o runner atual roda 2 vezes no frame | T17: 53 steps em 34 frames | Marcar como removido e compactar a lista no fim do frame |
| F16 | Alta | `CombatComponent.luau:430`, `WeaponTransform.luau:46-49` | `ApplyLoadout` apaga o loadout inteiro. Depois do WeaponTransform só sobra `Ability1`: não dá para voltar, e somem M1, Dash e Ult | T31 | Loadout em camadas (base + modo) ou merge por slot |
| F17 | Alta | `WeaponComponent.luau:180-181` | O modo Dual liga o mesmo `Handle` nas duas mãos (dois Motor6D na mesma peça). A arma flutua e troca de lado | T30 + screenshot do cliente | Exigir `Handle_secondary` ou clonar a peça; avisar quando faltar |
| F18 | Alta | `ReplicatedStorage.Assets.Weapons.Schema` | Duas pastas `Martelo` idênticas no nome; a legada não tem model. O `FindFirstChild` escolhe pela ordem, e na legada o `weaponModel:Clone()` dá erro | Seção de sincronização; T30 | Apagar a legada; validar duplicatas no boot (regra 19) |
| F19 | Alta | `Ultimate.luau:68-87`, `MovementController.luau:135-170` | O grab da Ultimate atrasa 10 a 17 studs, empilha os alvos, não solta no cancel nem na morte e dura 20 s a partir do hit | U1, U3, ult do player | Ver o bloco acima |
| F20 | Alta | `HealthComponent.luau:171-187` | A morte não encerra skills: caster morto continua voando; na arena houve até 3 mortos com skill ativa | U3, arena | `Die` cancela as skills ativas (ou emite um evento que o runner escuta) |
| F21 | Alta | `ControlComponent.luau:56-127` | Possessão aninhada: A continua achando que é controlado, o Release de B volta para A e, depois de soltar tudo, o input fica preso em A com o corpo server-owned | P2 + manual | Pilha de controle por player; `Possess` solta o anterior |
| F22 | Alta | `GlobalAntiCheat.luau:93-105`, `ControlComponent.luau:69/89`, `CameraOverride.luau:232-238` | O `suspendNative=true` é seguido de outra mensagem com `false` (`SetControlledEntity`), e o cliente reativa o WASD nativo durante a possessão | Log do cliente no P1 | Uma mensagem só, com o estado completo |
| F23 | Alta | `ControlComponent.luau:71-76` | O corpo abandonado continua andando com o último input (`DrivesInput=true` com direção velha) | P1: 15 studs em 1,2 s | Zerar `Direction` ao trocar o controlador |
| F24 | Alta | `ControlComponent.luau:56-94` | `Possess({AI=true, Brain})` não faz nada: o Brain é ignorado e a IA do alvo segue ligada | P4, P4b; arena 4 de 4 | Controlador de IA com Brain próprio e suspensão do AIComponent |
| F25 | Alta | `AnimationComponent.luau:193-218` | Repetir a animação na mesma key: o `Stopped` da track antiga apaga a nova. As tracks ficam órfãs tocando (65 depois do `StopAllAnimations`), o limite de 64 do Animator estoura e as conexões crescem 1 por play | T32 + console "AnimationTrack limit of 64 exceeded" | Só limpar se `Tracks[key] == track`; destruir tracks e desconectar |
| F26 | Alta | `Solvers/Blockcast.luau:10-20`, `Hitbox.luau:194-212` | O `HitStart` não zera `_LastCFrameBlockCast`: o primeiro cast sai da posição da ativação anterior | T28: acerto fantasma a 80 studs | Zerar no `HitStart` e no `SetCastData` |
| F27 | Alta | `Hitbox.luau:253-275` | O timer da hitbox desconta `delta` acumulado também nos frames pulados, e a duração real fica 14% menor | T27: `HitStart(1.0)` durou 0,86 s | Descontar o tempo real decorrido uma vez só |
| F28 | Alta | `Utils.luau:92` | O vetor "direita" tem o sinal invertido: andar para a direita é classificado como `Left` | T35 | `right = (-facing.Z, 0, facing.X)` |
| F29 | Alta | `AreaBehaviors.luau:14-22` | `DirectionalForce` no `OnStay` cria uma força nova a cada poll. As forças Soft se somam: 5 simultâneas e 100 studs/s em vez de 20 (padrão do `VentiladorDemo`) | Ambiente, teste de acúmulo | **Corrigido em 16/10**: `Key` no `AddForce` renova a força ativa; Key por zona via `opts.Area` (2º argumento dos callbacks do `AreaEffect`). Medido: pico 4 → 1 força, 80 → 20 studs/s; duas zonas sobrepostas (+30/−20) = 2 forças, +10 studs/s |
| F30 | Alta | `AreaBehaviors.luau:20` | O padrão `RequiresControl=true` faz o vento não empurrar alvo com Root ou Stun, contrariando a doc do Movement | ENV3: 0 stud com Root | **Corrigido em 16/10**: padrão `false` no `AreaBehaviors` (o `AddForce` genérico segue `true`); `RequiresControl = true` é opt-in. Medido: Root no vento padrão 0,0 → 29,4 studs em 1,2 s |
| F31 | Alta | `EntityWrapper.luau:235`, `CharacterComponent.luau:46-50` | A força de caminhada do NPC é fixa (2000): o chefe 5×7×4 não anda. Rig com Humanoid é tratado como sem Humanoid e anda \~1,6 stud/s | Manual (chefe parado), P4b | Força proporcional à massa; usar o Humanoid quando existir |
| F32 | Média | `Physics/Settings.luau:19` | Forças Soft quase não movem players (0,6 stud contra 20 esperados; 2,6 com `MaxForce` 35000): vento, esteira e knockback não valem para player | Sondas de força no player, S8 | Força em função da massa e do controlador do Humanoid; ownership do servidor durante a força |
| F33 | Média | `MovementController.luau:211`, `Physics/Settings.luau:13-19` | Corpo pesado ignora toda força Soft (vento e knockback: 0 stud) | ENV1, ENV8 | Opção de impulso ou aceleração por massa |
| F34 | Média | `MovementComponent.luau:212-218` | NPC perto do player fica com ownership do cliente (auto-ownership): o cliente simula a física do NPC | T51 | `SetNetworkOwner(nil)` no `SetMovement` |
| F35 | Média | `EntityCore.luau:192-206` | `RemoveComponent` deixa as closures da API na entidade: a chamada vai para o componente destruído, dá erro e vaza a cadeia | T02 | Apagar as chaves expostas no `RemoveComponent` |
| F36 | Média | `MovementComponent.luau:151-167`, `DataManager.luau:98-101` | Movement sem Character derruba o `DataManager.Create` e deixa a entidade meio registrada | T05 | Declarar `Requires = {"Character"}` e validar antes de registrar |
| F37 | Média | `EntityCore.luau:276-281`, `EntityCore.luau:348-358` | `RegisterComponent` não copia `EventKey`, então `EntityCore.Events` fica sempre vazio | T06 | Copiar `EventKey` no registro |
| F38 | Média | `DataManager.luau:200`, `EntityCore.luau:247` | `IsNPC()` é sempre falso: o DataManager grava `Type = "Entity"` | T04 | Unificar os tipos num enum |
| F39 | Média | `StatusComponent.luau:117-233` | Status é aplicado em entidade morta | T46 | Recusar ou política configurável |
| F40 | Média | `SkillRunner.luau:149-157` | Todo runner, inclusive de status, entra em `ActiveSkills` e vira dono da hitbox da arma. `StopAllActiveSkills` derruba os status | T47 | Registrar só runners do tipo Skill. **Corrigido em 16/10** (F1.5 do hardening): só runners `Skill` entram em `ActiveSkills` e viram donos da hitbox da arma; a remoção do owner ficou simétrica (com Weapon e sem Combat o runner ficava dono para sempre). Teste F1.5 do `IntegrationTests`: com um status homônimo ativo, a 2ª ativação cria runner novo; o status fica fora de `ActiveSkills` e sobrevive ao `StopAllActiveSkills` |
| F41 | Média | `HealthComponent.luau:97`, `HealthComponent.luau:130-134` | Hit 100% bloqueado ainda aplica efeitos on-hit; hit de 0 de dano não aplica efeito (slow puro impossível) | T44 | Política de efeitos por resultado do hit |
| F42 | Média | `AttributesComponent.luau:32-46` | `GetStat` guarda em cache o valor calculado com o primeiro default | T37: 2ª chamada com default 9 devolveu 5 | Não cachear quando a base vem do default |
| F43 | Média | `AttributesComponent.luau:142-143` | `Defense` e `DamageMult` são inicializados mas nunca entram no dano | Teste limpo: dano 10 → 10 com ×2 e Defense 50 | Fórmula de dano declarada num lugar só (regra 17) |
| F44 | Média | `AreaEffect.luau:84-88` | `Stop()` não dispara `OnExit`: o efeito aplicado na entrada fica preso | T53: slow preso | Disparar `OnExit` para quem está dentro |
| F45 | Média | `AttributesComponent.luau:113-127` | Modificadores sem contagem de referência: duas zonas com o mesmo ID, sair de uma tira o efeito de dentro da outra | ENV6 | Chave por instância de fonte, ou refcount |
| F46 | Média | `EntityWrapper.luau:308-323` | Força Soft substitui a locomoção do NPC no eixo: andar contra esteira é impossível (+11 em vez de −6) | ENV7 | **Corrigido em 16/10** (D6, decisão do usuário): alvo do eixo Soft = caminhada pretendida + soma das Soft; o eixo fecha quando uma Soft o reivindica, então vento só em X não tira mais a caminhada em Z. Medido: NPC contra esteira de +10 andando a 16: +10,0 → −6,0; player (WalkSpeed 20) no vento +10 com `MaxForce` 35000: parado +9,7, contra −10,0, de lado +10,1/+20,0. NPC com Humanoid segue lento por causa do F31 |
| F47 | Média | `MovementController.luau:237-243` | `canDisplace=false` cancela também o dash da própria entidade | ENV4 | Separar forças próprias das externas |
| F48 | Média | `TriggerSet.luau:100` | `Emit` com context nil dá erro fora do `pcall` | T26 | Context padrão `{traits = {}}` |
| F49 | Média | `DataManager.luau:118-119`, `SkillHandler.luau:185` | `DataManager.Get(nil)` e `HandleIntent(id, nil)` dão erro (IA com bug derruba o loop) | T49 | Validar entrada |
| F50 | Média | `EntityWrapper.luau:134`, `EntityWrapper.luau:242` | Entidade criada com raiz ancorada nunca ganha ForceRig e fica imóvel em silêncio. Os 4 rigs do place são ancorados | U1 (1ª rodada) | Criar o rig sempre, ou avisar |
| F51 | Média | `TriggerSet.luau:71-82`, `Dash.luau:64-67`, `Dash.luau:85` | Owner em string é global: limpar o combo de um atacante remove os listeners de outro | T25 | Token de dono por instância com TTL |
| F52 | Média | `TriggerSet.luau:46-52` | `Subscribe` reordena a lista inteira a cada inscrição: 3000 listeners custam 3,2 s de CPU | T23 | Inserção ordenada (binária) |
| F53 | Média | `SkillRunner.luau:194` | `BuildContext()` aloca tabela por runner por frame: 3000 runners deram frame médio de 25,7 ms e máximo de 78 ms | T16 | Reusar o context ou criar sob demanda |
| F54 | Média | `SkillRunner.luau:327-355` | `onEnd` roda depois do `onCancel` sem dizer o motivo: recarga interrompida recarregou 6 balas | K1 | `onEnd(reason)` |
| F55 | Média | `M1.luau:24`, `SkillRunner.luau:64-67` | Skills não são portáveis: o M1 da Schema dá erro fora da Schema (`charLib` nil) | K5 | Kit injeta a biblioteca de animação; skill declara dependências |
| F56 | Média | `HealthComponent.luau:47-51` | HUD durante possessão mostra o HP do corpo original | P6 + screenshots | HUD segue a entidade controlada |
| F57 | Média | `CameraOverride.luau:206-214` | A câmera da possessão só acha models filhos diretos do workspace e já replicados. Com `StreamingEnabled` ligado, o Rig padrão não foi achado em 4 tentativas; o model `Persistent` funcionou | P7 e manual | Enviar a Instance no remote; ajustar `ReplicationFocus` |
| F58 | Média | `SkillHandler.luau:16-24` | Input roteado para entidade sem Movement (torre) gera 1 warn de stub por `RequestDir` | Manual: 32 warns em 1,5 s | Checar capacidade antes de rotear |
| F59 | Média | `IntegrationTests.server.luau:78-79` | O teste de Tether da suíte original roda nas mesmas coordenadas do GrandIntegrationDemo e falha por interferência (drift de 4,6 studs; isolado: 0,13) | T38 | Zona própria por teste. **Corrigido em 16/10**: cada teste do `IntegrationTests` roda numa faixa própria (plataforma em x ≥ 1400, longe da origem), e o `makeDummy` recebe a posição relativa a ela. Medido: deriva do Tether no boot 3,5 studs (falhou) → 0,08 e 0,22 em duas rodadas, 10/10 |
| F60 | Média | `GrandIntegrationDemo.server.luau:97` | `self.target.Entity:GetDescendants()`: EntityCore não tem `.Entity`, dá erro quando o alvo morre | Leitura | `self.target.Instance` |
| F61 | Média | `CombatComponent.luau:555-581`, `CombatComponent.luau:73-184` | `SetChosenChar` chama uma API que não existe (`SetAttribute`) e mistura formatos de stats; o caminho legado `CharData` está morto | Leitura | Remover ou reescrever sobre `SetCharMode` |
| F62 | Média | `StateTable/Helper.luau:46-58`; teste em linha | Cadeia síncrona longa é cortada em silêncio (51 de 80 alvos); cadeia assíncrona não tem limite (profundidade 81; árvore com 1023 runners) | T22, cadeia em linha | Fila diferida com orçamento por frame |
| F63 | Média | `CharacterComponent.luau:45` | Player sem HRP usa a própria tabela como root (`or Entity`) | Leitura | `model.PrimaryPart` |
| F64 | Baixa | `DataManager.luau:22-103`, `EntityCore.luau:283` e outros | Saída de debug como warn estrutural: cerca de 8 warns/s na arena (2.340 em 5 min) | Arena | Logger com níveis (regra 18) |
| F65 | Baixa | `CombatComponent.luau:625` | `ApplyDamage` em alvo sem Health devolve nil, e o guarda `type(TakeDamage)` não serve (o stub é função) | T45 | Checar `HasComponent("Health")` |
| F66 | Baixa | `StatusComponent.luau:187` | O campo `entry.counter` fica sempre 1 (o real está em `runner.skill.counter`) | T07 | Remover o campo |
| F67 | Baixa | `StatusComponent.luau:213-220` | Status `exclusive` não remove stacks em lista da mesma categoria | Leitura | Tratar listas |
| F68 | Baixa | `Combat/Types.luau:37-56` | `Context` declarado diferente do que `BuildContext` gera; `Subscription.Role` diz Target/Source, mas o Enum usa IN/OUT | Leitura | Um tipo dono (regra 17) |
| F69 | Baixa | `ServerStorage/!DOC/DOC.luau` | DOC desatualizado (CombatData, TryHit, CharData) e duplicado em `CharData/!Doc` | Leitura | Atualizar e manter 1 cópia |
| F70 | Baixa | `.agents/`, `sprints.md` | Commitados, embora as regras peçam `.gitignore` | git | Adicionar `.gitignore` |
| F71 | Baixa | `PlayerGui.CooldownGUI.Attacks` | Botões Skill1-3 sem o atributo `Intent` (warn a cada spawn) | Console | Preencher o atributo |
| F72 | Baixa | `AnimationComponent.luau:376-395` | `WaitForMarker` com timeout sempre espera o tempo inteiro | Leitura | Retornar no disparo |
| F73 | Baixa | `Animation/AnimationController.luau` | Duplica a lógica de tracks do AnimationComponent (regra 1) | Leitura | Remover |
| F74 | Baixa | `Helper.luau:196-214` | Duas imunidades com a mesma tag: vence a última do `pairs()` (não determinístico) | Leitura | Mesclar regras |

### Achados novos (16/10/2026, na aplicação do lote P0)

Encontrados ao aplicar e testar o P0. F75 a F84 seguem abertos, menos o F76, corrigido no Passo 0 do F05. F85 a F91 foram corrigidos junto com o item do P0 que dependia deles e ficam aqui pelo histórico; o F92 apareceu no teste do validador do F05 e foi corrigido junto. O F93 saiu da conferência do documento de hardening e segue aberto. Linhas conferidas no código de 16/10.

Decisão do usuário (16/10): não matar o Humanoid quando o HP do framework zera é intencional; o que acontece com HP 0 fica a critério do dev final. O F75 trata só da inconsistência entre as regras de morte que o motor já aplica.

| # | Sev. | Onde | O que acontece | Evidência | Correção |
| --- | --- | --- | --- | --- | --- |
| F75 | Média | `SkillHandler.luau:131`, `CombatComponent.luau:313-324` | Entidade com `IsDead` ainda aceita cast novo e causa dano, embora o motor já recuse dano (`TakeDamage`), recuse status (F39) e cancele as skills ativas na morte (F20). O gate de cast só olha a tag `canCast` | Teste: caster com `IsAlive() = false` ativou a skill e causou 7 de dano | Nova regra no `Enum.DeathDefaults` (ex.: `RefuseCastOnDeath`), no mesmo mecanismo que já torna F20 e F39 configuráveis (16/10) |
| F76 | Alta | `MovementController.luau:211`, `MovementController.luau:248` | O `MaxForce` de força Soft é ignorado: o orçamento é calculado, mas os eixos Soft sempre recebem `Soft_Force_Strength` (2500). O `MaxForce = 35000` do VentiladorDemo nunca vale, e no chão a frenagem do Humanoid vence o vento | Ventilador de 30 studs/s no player parado no chão: 1,4 stud em 1,5 s (1 stud/s; no ar, 27 studs/s). Com o teto em 35000 (experimento em runtime): 141 studs em 1,5 s, a 149 studs/s por causa do F29 | **Corrigido em 16/10**: orçamento por eixo = maior `MaxForce` entre as Soft que reivindicam o eixo (padrão `Soft_Force_Strength`). Medido: corpo pesado (massa 98) no vento de 30 com `MaxForce` 35000: 0,0 → 42,4 studs em 1,5 s, velocidade máxima 30,0 |
| F77 | Média | `StatusComponent.luau:188-200` | `ApplyStatus` num status `stackOnSelf` (incremento ou já no máximo) devolve um ID novo, que não existe; `RemoveStatusByID` com ele falha | Teste: 2º e 3º `ApplyStatus` com IDs diferentes do guardado; `RemoveStatusByID(id2) = false`, status segue ativo | Devolver `existing.ID` |
| F78 | Média | `SkillScheduler.luau:35-38`, `SkillRunner.luau:372-389` | Erro no `onStep` de uma skill cujo `onCancel` recusa o cancel (`return false`): o runner continua vivo e erra a cada frame | Teste: 18 warns em 18 frames (1 s), runner vivo | Erro força o fim sem veto, como o `start()` já faz no erro do `onStart` |
| F79 | Média | `HitboxWrapper.luau:146-148`, `HitboxWrapper.luau:272`, `M1.luau:39`, `M1.luau:75` | A hitbox da arma é compartilhada: `StartHitbox` de uma skill é recusado se outra ainda tem hitbox ativa (a duração dela não vale), e o `StopHitbox` da limpeza do M1 desliga a hitbox de quem estiver usando | Leitura | Hitbox por owner (ou contagem de referência com duração por owner) |
| F80 | Média | `SkillRunner.luau:406-412` | `OUT.onEnd` só é emitido quando a entidade tem Combat, mas `OUT.onStart` vale para qualquer entidade: listener de fim nunca dispara num runner de entidade sem Combat | Leitura | Emitir `OUT.onEnd` fora do `if` de Combat. **Corrigido em 16/10**: emitido para qualquer entidade, como o `OUT.onStart`. Teste F80 do `IntegrationTests`: entidade só com Health recebe `OUT.onStart` e `OUT.onEnd` (1× cada, `reason = stop`) |
| F81 | Baixa | `WeaponTransform.luau:2`, `WeaponTransform.luau:17` | Com `duration = 0`, a troca de modo acontece no 1º frame, embora o NoControl dure `TransformTime` (0,5 s): a janela de cancelamento é de 1 frame | Teste: troca Dual → Merged em menos de 0,3 s | `runtimeDuration = TransformTime` no `onStart` |
| F82 | Baixa | `GlobalAntiCheat.luau:34-44` | `AntiCheat.Register` recria o estado do player no respawn (`Locked = false`): um Lock de cutscene não sobrevive ao respawn | Leitura | Preservar `Locked` e `PreLockID` no `Register` |
| F83 | Baixa | `GlobalAntiCheat.luau:15`, `CameraOverride.luau:206-230` | Lock durante possessão manda a câmera de volta ao corpo nativo: o Lock envia `entityID = nil`, e o cliente trata nil como "voltar ao próprio corpo" | Leitura | Mandar o ID roteado também com `isLocked = true` |
| F84 | Baixa | `SkillFactory.luau:67-86` | `StatusController` é código morto: nada preenche `originalData.StatusController` | Busca no código | Remover |
| F85 | Alta | `CombatComponent.luau:405` | `StopAllActiveSkills` percorria a lista enquanto `RemoveActiveSkill` a encolhia: com `maxInstances > 1`, metade dos runners era pulada, e o `table.clear` final os tirava do registro ainda rodando (inclusive os que recusaram o cancel) | Leitura; o F20 dependia disso | **Corrigido em 16/10**: snapshot e filtro por tipo de runner |
| F86 | Média | `StatusComponent.luau:259` | O status só era registrado depois do `start()`: um status que falhava ou se encerrava no próprio `onStart` deixava a entrada com runner morto e as tags valendo (o `Bleed` documentava `GetStatusCounter = 0` no `onStart`) | Leitura; o F14 dependia disso | **Corrigido em 16/10**: `_StartRunner` registra antes de iniciar |
| F87 | Média | `SkillFactory.luau:76-89` | O wrapper de `onEnd`/`onCancel` dos status repassava só o `selfRunner` e descartava o ctx | Leitura; o F54 dependia disso | **Corrigido em 16/10**: repassa o ctx (com `ctx.reason`) |
| F88 | Média | `ControlComponent.luau:382-401` | O `Unlock` destravava o controlador ATUAL: com a pilha de controle, trocar de corpo durante um Lock deixaria o player travado (latente, exposto pela correção do F21) | Leitura | **Corrigido em 16/10**: o `Unlock` desfaz exatamente o que o `Lock` cortou |
| F89 | Baixa | `SkillRunner.luau:312` | Limpeza registrada com `Own()` depois do fim do runner nunca rodava (ex.: `onHit` atrasado, grab nunca solto) | Leitura | **Corrigido em 16/10**: roda na hora |
| F90 | Baixa | `SkillRunner.luau:196` | `OUT.onStart` era emitido depois do fim quando a skill se encerrava dentro do próprio `onStart` | Leitura | **Corrigido em 16/10**: não anuncia início depois do fim |
| F91 | Baixa | `StatusComponent.luau:226` | O laço de status `exclusive` removia entradas durante o `pairs` do mesmo grupo (callbacks de fim podem inserir chaves) | Leitura | **Corrigido em 16/10**: snapshot dos nomes |
| F92 | Média | `CameraOverride.luau:232-238` | No Lock (e ao dirigir outro corpo) o cliente troca o `moveFunction` por uma função vazia, mas `Humanoid:Move` persiste até a próxima chamada: quem estava andando quando o Lock chegou seguia na última direção até o Unlock, no meio da cutscene. Com o validador do F05 (caminhada zerada no Lock) isso virava correção num player legítimo | Teste de 16/10: player andando, Lock por 1 s: seguiu andando, 2 correções | **Corrigido em 16/10**: o cliente para o corpo (`Move` zero e `Jump = false`) ao suspender o controle nativo. Medido: 0,7 stud no segundo de Lock, 0 correções |
| F93 | Baixa | `Main.server.luau:75-108` | Os comandos de chat `;bleed` e `;moveblock` usam API que não existe mais (`ED.CombatData`, `cd:Count`, `cd:Remove`) e chamam `ApplyStatus` com a entidade no lugar da duração: dão erro se alguém digitar | Leitura (16/10) | Remover, ou migrar para a API atual se ainda forem úteis |

## Brechas de abstração e assunções escondidas

O motor ainda pressupõe um battleground com personagens fixos: 6 botões, um kit por personagem do banco, assets pelo nome do personagem, dano sem fórmula e player com Humanoid controlado pelo cliente. Os 13 kits hipotéticos precisaram de 17 workarounds diferentes para contornar essas assunções.

| Assunção ou lacuna | Onde | Impacto | Direção |
| --- | --- | --- | --- |
| Intents fixas (6 botões) | `Input/Intents.luau` (tabela congelada) | Minigame, QTE, seleção de bala, carta 4 ou combo de teclas exigem editar o motor | Intents registráveis por dado e contextos de input por skill |
| Combat exige personagem no `CharacterDatabase` | `CombatComponent.luau:52-53, 589-610`; banco congelado | Kit criado em runtime (roguelike, cartas, boss que muda de kit) precisa de `ChosenChar` falso; todo NPC com Combat nasce com o kit Schema | Combat sem personagem; kit como dado injetável |
| Assets pelo nome do personagem | `Assets.Weapons.<Char>.<Arma>`, `AnimationLib.character[<Char>]`, `self.charLib` | Arma não é compartilhável e skill não é portável (M1 da Schema quebra fora dela) | Assets por ID; kit injeta biblioteca |
| Player = Humanoid, NPC = sem Humanoid | `CharacterComponent.luau:42-50` | Rig de NPC com Humanoid é ignorado e anda devagar; player não recebe força Soft | Detectar Humanoid, não o tipo de entidade |
| Sem time ou facção | Hitbox, AreaEffect, kits | Toda hitbox acerta aliado; cada kit filtra por um campo ad-hoc (`entity.Team`) | Componente de Afiliação com política de fogo amigo |
| Sem API de alvo no servidor | (não existe; o lock-on é só da câmera) | Skill de alvo, marca, auto-aim e IA reimplementam cone, raio e linha de visão | `Targeting.Query({cone, raio, LOS, time})` |
| Sem componente de recurso | (não existe) | Munição, mana, tambor e combo viram status infinito ou stat numérico; nada emite evento de mudança | Resource/Blackboard com eventos |
| Sem canal de estado para o cliente | Remotes fixos `UpdateHealthBar` e `SkillFired` | HUD de munição, tambor ou fase do chefe só via `Instance:SetAttribute` fora do framework | Replicação declarativa de campos escolhidos |
| API de dano estreita | `SkillRunner:Damage(target, amount)`, `Helper.BuildContext` | Sem traits por hit, tipo, ponto ou direção do impacto; `context.direction` é a intenção de movimento do atacante | `Damage(target, {amount, traits, type, point, direction})` |
| Sem fórmula de dano | `Defense` e `DamageMult` sem uso | Enrage, armadura e crítico precisam de listener manual | Fórmula declarada num lugar só |
| Política fixa de atributos | `AttributesComponent.luau:56-78` | Override sempre pelo menor valor e só na base (Flat ainda soma); tudo travado em ≥ 0 (sem gravidade invertida) | Resolução por prioridade; limites por stat |
| Política fixa de cooldown | `SkillHandler.luau:81-85, 105` | Sem cargas, sem cooldown no fim, sem grupo compartilhado; o recast é bloqueado pelo próprio cooldown | Política por skill (`onStart`/`onEnd`/cargas) |
| Loadout sem camadas | `CombatComponent.luau:421-445` | Troca de modo apaga o loadout | Pilha de loadouts (base, forma, buff) |
| CC não interrompe skill | `SkillRunner`, `StatusComponent` | Canal, recarga e voo seguem durante Stun; a morte não para nada | Política de interrupção por tag (`interruptibleBy`) |
| Ciclo de vida ambíguo | `SkillRunner.luau:172-204, 322-373` | `castTime` só atrasa o `onStep` (sem `onCastComplete`); `onEnd` roda após o cancel sem motivo | Breakpoints `onCastComplete` e `onEnd(reason)` |
| Dois "Context" | `Helper.BuildContext` × `SkillRunner:BuildContext`, `Types.luau` | O design de Context por breakpoint não foi entregue: `inherited` está sempre vazio | Um tipo só, com `inherited` preenchido no ponto de injeção |
| Lineage sem dono do minion | `MinionFactory`, `Lineage.luau` | Crédito de kill e lifesteal do invocador só por listener herdado; o Fork é uma foto no spawn | `Lineage.Owner` e vínculo de ciclo de vida |
| Recursão síncrona e global | `Helper.luau:46-58` | Cadeia estilo Isaac é truncada em silêncio em 50; assíncrona não tem limite | Fila diferida com orçamento |
| Possessão depende de Control no alvo | `Main.server.luau:11-20` (player sem Control) | Player não pode ser possuído por padrão; torre precisa de `AddComponent` em runtime; possessão não pausa a IA do alvo (decisão do sprint 15, mas é armadilha) | Controle como pilha com política de IA explícita |
| Forças sem massa | `Physics/Settings.luau`, `EntityWrapper.luau:235` | Mesma força move o enxame e não move o chefe; Soft substitui a caminhada do NPC; player e NPC reagem diferente | Modo por aceleração ou impulso |
| Singletons globais | `SkillScheduler`, `MovementController`, `AIScheduler`, pool de hitbox | Sem escopo por partida ou zona (pausar uma arena, rodar duas partidas, testes isolados) | Contexto de mundo injetável |

**Regras do `.agents` que o código atual quebra**

- Regra 1 (DRY): `AnimationController` duplica o AnimationComponent; o DOC está duplicado.
- Regra 5 (entidade simples barata): toda criação imprime 4 ou mais warns; o NPC sem Humanoid paga raycast em `GetAirState`.
- Regra 12 (sem valores soltos): `targetEntity.forceID` (Ultimate), `HunterIgnoreSet` (demo) e o `entity.Team` dos kits.
- Regra 16 (dependência explícita): só o Animation declara `Requires`.
- Regra 17 (formato com dono único): dois Contexts, dois históricos (`ChainHistory` legado × `Lineage`), `JumpPower` × `JumpForce`, `baseStats` × `BaseStats`.
- Regra 18 (debug padronizado): `VITALS`, `print` no Weapon, `warn` no Bleed e no VFXPlayer.
- Regra 19 (sem nomes duplicados): `Martelo` em dobro, `Workspace.martelo`, DOC em dois lugares.
- Regra 20 (componente auto-suficiente): `HasComponent` condicional em Weapon, Movement, Health, Combat, Animation e SkillRunner.

## Estudo de caso: a Pistoleira e os outros kits

A Pistoleira do seu exemplo roda hoje sem mexer no motor, mas com 6 workarounds e 1 falha que não tem contorno limpo (recarga interrompida). Ela foi implementada e testada: modo melee com adagas duplas, revólver de média distância, tambor de 6 câmaras com balas tipadas, roleta skillcheck, buff persistente, marca de alvo, munição e HUD. Na arena ela disparou 135 tiros (mais 52 cliques com o tambor vazio), parou 17 roletas (7 ótimas), gerou 94 balas especiais e acertou 21 golpes no alvo marcado.

| Requisito | Resultado | Como foi feito | Custo |
| --- | --- | --- | --- |
| Trocar melee ↔ ranged numa skill | Funciona com workaround | Troca slot a slot com `EquipSkill`/`UnequipSlot` | `ApplyLoadout` apaga o loadout (F16) |
| Adagas duplas | Parcial | Melee por cone no servidor | O modo Dual prende o mesmo Handle nas duas mãos (F17) |
| Pistola de média distância | Funciona | `workspace:Raycast` ao longo do `AimDirection` (60 studs) | Sem compensação de latência; o servidor não sabe a origem da câmera de ombro, então a mira diverge da cruz |
| Roleta estilo DBD | Funciona com workaround | Ponteiro no servidor (`onStep`), parada por recast, cursor do tambor = ponteiro | O cooldown bloqueia o recast (F12): roleta com cooldown 0 e o real via `task.defer`. O acerto é julgado pela chegada no servidor, então o ping decide |
| Buffs que persistem entre estados e skills | Nativo | Status `Foco` com `Listen` OUT.onHit (+30%) | Nenhum: sobreviveu à troca de modo e multiplicou 6 → 7,8 |
| Skill de alvo (marca) | Funciona com workaround | Alvo escolhido à mão; listener +50% só no marcado | Sem API de alvo |
| Contagem de munição | Funciona com workaround | Tambor guardado num status infinito | Sem componente de recurso |
| Balas geradas por ações | Nativo | `Listen` OUT.OnDamage com `Query = {Any = {Melee}}` | Nenhum: 6 balas especiais em 10 golpes |
| Tambor visível na HUD | Só por fora do framework | `Instance:SetAttribute` no model | Sem canal de replicação |
| Escolher a bala pela roleta | Funciona | Cursor recebe o índice do ponteiro | Nenhum |
| Bala perfurante (ignora iFrame) | Funciona com workaround | `Listen` OUT.onHit de uso único injeta TrueHit no context | `Damage` não aceita traits por hit |
| Recarga interrompível por Stun | Falha | Checagem de `canCast` no `onStep` com `Stop(true)` | O `onEnd` roda após o cancel e recarregou 6 balas mesmo interrompida (F54) |

Para fechar o seu exemplo sem gambiarra, o motor precisa de: loadout em camadas, política de cooldown com recast livre, `Damage` com opções por hit, `onEnd(reason)`, componente de recurso com replicação, e um primitivo de input temporizado que use o timestamp do cliente validado contra o RTT.

**Os outros 12 kits (só API pública, na arena todos contra todos)**

| Kit | Funcionou nativo | Precisou de workaround | Bloqueado ou quebrado |
| --- | --- | --- | --- |
| Invocador | On-hit herdado pelos minions (225 marcas aplicadas por minion) | Morte do dono mata os minions (listener manual); crédito de kill via OUT.OnDeath herdado (45 créditos) | Listener criado depois do spawn não chega ao minion |
| Duelista | Parry anula, atordoa e zera o cooldown; counter-hit no castTime | Nenhum | Quebra-guarda rompe bloqueio Unbreakable (F10) |
| Alquimista | Reação em cadeia densa: 64 de 64 em 70 ms | Precisa assinar OnDeath em cada alvo | Cadeia em linha para em 51 de 80 (F62) |
| Ladrão | Roubo de skill com herança de cooldown | Possessão de IA feita à mão | M1 roubado da Schema quebra (F55); `Possess(AI)` não assume (F24) |
| Cronomante | Rewind de posição e HP | Histórico guardado num status | Nenhum |
| Canalizador | Hold/Release com HeldTime (15 de dano a 1 s) | CC checado à mão no `onStep` | Nenhum |
| Mestre de Cartas | Compra de cartas em runtime | Mana como stat; devolve o cooldown quando falta mana (403 casts sem mana) | Nenhum |
| Colosso (chefe) | Fases por HP, iFrame na transição, adds | `castTime` sem breakpoint de fim | Não anda (F31); enrage por `DamageMult` sem efeito (F43) |
| Torre | Escudo frontal e projétil teleguiado | Escudo usa a posição do atacante (não há ponto do impacto) | Sem Control não é possível possuir; possuir a partir dela quebra (F04) |
| Espelho | Copia a última skill que o atingiu: pelo menos 12 skills de 8 kits | Módulo remontado a partir do runner | Nenhum |
| Enxame | 1.776 casts e 303 mortes sem erro | Nenhum | Nenhum |
| Possessor | Nenhum | Tudo manual | Possessão oficial de IA falhou 4 de 4 |

## Recomendações e próximos passos

Corrija primeiro o que derruba o servidor ou o player (P0), depois o que faz mecânicas centrais mentirem (P1), e só então abra os componentes novos (P2). Pela regra 7 do `.agents`, um módulo por vez, rerodando a suíte desta auditoria a cada sprint.

**P0: antes de qualquer conteúdo novo**

1. Cadeia de recursão (F01): miolo de `TakeDamage`/`ApplyStatus` em `pcall`, com saída da cadeia garantida. Melhor ainda, profundidade carregada no context, não global.
2. Autoridade de movimento (F05): escolher entre corpo server-owned com predição no cliente, ou corpo do cliente com validação de velocidade e teleporte e correção. Nos dois casos, Stun, Root e Lock precisam valer no servidor.
3. Possessão (F02, F03, F04, F21 a F24): pilha de controle por player; `Release` automático em `Destroy` e na morte; ownership só em peça válida e não ancorada; respawn criando o corpo antes de soltar; uma única mensagem `ControlStateChanged`; controlador de IA de verdade.
4. Status (F06 a F09): snapshot em `RemoveStatus`, `RemoveStatusByID` e `ClearAll`; corrigir `SkillRunner:ApplyStatus`; recusar status em entidade morta.
5. Ciclo de vida das skills (F13, F14, F20, F54): `pcall` em todos os callbacks; `onEnd(reason)`; a morte cancela as skills ativas.

**P1: mecânicas que hoje mentem**

6. Bloqueio e escudos (F10, F11): traits lidas do meta; `ShieldsFrom` bloqueando por padrão; política de efeitos para hit bloqueado e para hit de 0 de dano (F41).
7. Ultimate da Schema (F19): grabs do runner com `Own`, duração restante, feed-forward no `FollowTarget`, offsets por alvo e CollisionGroup.
8. Forças (F29 a F33, F46, F47): upsert de força por ID no `AreaBehaviors`; `RequiresControl=false` para ambiente; força de caminhada e forças Soft proporcionais à massa; Soft somando com a locomoção; separar forças próprias de externas; player afetado como NPC.
9. Loadout em camadas e política de cooldown com recast livre (F12, F16).
10. Hitbox (F26, F27) e arma (F17, F18): zerar o Blockcast no `HitStart`, corrigir o timer, `Handle_secondary` no Dual, apagar o `Martelo` duplicado.
11. Animação (F25): dono da track por key, destruir tracks antigas, limitar conexões.
12. Direção (F28): corrigir o sinal do vetor lateral antes de criar combos direcionais.

**P2: tirar as assunções**

13. Componentes novos: Resource/Blackboard com eventos e replicação, Targeting, Afiliação (time e fogo amigo), canal de estado para HUD.
14. Input: intents e contextos registráveis por dado; input temporizado com timestamp do cliente validado contra o RTT, para skillchecks justos.
15. Dano: `Damage(target, options)` com traits, tipo, ponto e direção do impacto, mais uma fórmula única que use `Defense` e `DamageMult`.
16. Kits como dado: Combat sem `CharacterDatabase` obrigatório, assets por ID, skills portáveis (o kit injeta a biblioteca de animação).
17. Recursão: fila diferida com orçamento por frame, para cadeias estilo Isaac não serem cortadas em silêncio.
18. Higiene: logger com níveis; `Requires` em todos os componentes; `.gitignore` para `.agents` e `sprints.md`; testes em zona própria; levar a suíte `audit_suite` para o repo.

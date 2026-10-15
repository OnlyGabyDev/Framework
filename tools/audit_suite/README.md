# audit_suite — testes da auditoria de 15/10/2026

Suíte usada na auditoria "Framework de Combate — Auditoria de Falhas e Brechas".
A auditoria completa está em [`AUDITORIA.md`](AUDITORIA.md) (cópia em Markdown); a versão viva,
com comentários, fica no claude.ai: https://claude.ai/code/artifact/46b99f1b-a621-440c-a492-107e7e5c1e9f.
O lote P0 pronto para outra sessão aplicar está em [`HANDOFF_P0.md`](HANDOFF_P0.md).
Cada teste mede um comportamento e compara com o contrato esperado. Os IDs `F01..F74`
são as falhas do doc; rode de novo depois de cada correção e compare com a coluna "auditoria".

Esta pasta fica **fora de `sync/`** de propósito: nada aqui vai para o place pelo sync.

## Pré-requisitos

- Studio em **Play** (não Run): BatchP, BatchU2, Sec e as sondas de player usam o player real.
- `workspace.Rig` existindo (BatchC, BatchP, BatchU, Caps K5 clonam ele).
- Pasta `ServerStorage.__AUDIT` (Folder). A maioria dos scripts cria; Caps, Arena e Env exigem que já exista.
- `modules/__AuditKitLib.luau` e `modules/__AuditKits.luau` como **ModuleScripts em ServerStorage**
  (nomes `__AuditKitLib` e `__AuditKits`) para Caps, Arena e as sondas.

## Como rodar

1. Play no Studio.
2. Crie os ModuleScripts acima em ServerStorage.
3. Crie um `Script` em ServerScriptService com o conteúdo de um arquivo de `server/` ou `probes/`.
   Scripts de `client/` vão como `LocalScript` em `Players.<você>.PlayerGui`.
4. Leia o resultado: `ServerStorage.__AUDIT.<Nome>` (StringValue com JSON: `results[].checks[]`,
   `metrics`, `server_errors`) ou o atributo indicado no cabeçalho das sondas.

### Rodando por um agente com o MCP do Studio (o que a auditoria fez)

- `execute_luau` roda numa **VM separada** do jogo: `require(DataManager)` ali enxerga outro registro
  (o player não aparece). Por isso o agente cria um `Script`, seta `Source` e dá parent em
  ServerScriptService; assim o código roda **na VM do jogo**.
- **Não destrua o Script injetado antes de ele terminar**: as conexões criadas por ele morrem junto.
- O teclado virtual do Studio é recusado (`VirtualInput ... cannot process this key`). Para "jogar",
  use os drivers de `client/`, que mandam os mesmos remotes do `InputService`. O clique do mouse funciona.
- O `GrandIntegrationDemo` nasce na origem e possui o player aos 5 s: os testes usam zonas a 800+ studs.
- `StreamingEnabled` está ligado: models longe do player podem não existir no cliente.
- A BatchA mede vazamento do `MAX_RECURSION` e **restaura** o contador; se um teste seu vazar, chame
  `StateTable.ExitChain()` o número de vezes vazadas antes de continuar.

## Arquivos e o que verificam

| Arquivo | Testes | Falhas do doc | Auditoria (antes) | Esperado depois |
| --- | --- | --- | --- | --- |
| `server/__AuditBatchA` | T01-T15, T44-T50 | F01, F06-F11, F35-F39, F40, F41, F49, F65, F66 | 17 de 22 falharam (T08: 5/10 órfãos; T14: 10/10 vazaram) | T08 e T50: 0 órfãos; T09: sobram 4; T14: 0 vazamentos |
| `server/__AuditBatchB` | T16-T26, T39 | F12-F15, F48, F51-F53, F62 | 9 de 12 falharam (T17: 53 steps em 34 frames) | onStep 1x por frame; recast dentro do cooldown |
| `server/__AuditBatchC` | T27-T38, T51, T53 | F16, F17, F25-F28, F34, F42, F44, F59 | 9 de 12 falharam (T27: 0,86 s; T28: hit fantasma) | HitStart(1.0) ≈ 1,0 s; Right = "Right" |
| `server/__AuditBatchP` | P1-P8 | F02, F03, F21, F23, F24, F56, F57 | 7 de 8 falharam (P8: player sem entidade) | Rota volta ao corpo em todos |
| `server/__AuditBatchU` / `U2` | U1-U3, P4b | F19, F20, F24, F31, F50 | U2 tem os rigs desancorados (use o U2) | Grab < 2 studs; solta no cancel e na morte |
| `server/__AuditCaps` | K1-K8, E1-E3 | F10, F43, F54, F55, F62 | 4 de 11 falharam | Recarga interrompida não recarrega |
| `server/__AuditArena` | arena 300 s (atributo `ArenaDuration`) | estabilidade | 0 erros; 2.340 warns; até 3 mortos com skill | 0 erros; warns perto de 0; 0 mortos com skill |
| `server/__AuditEnv` | ENV1-ENV14 | F29-F33, F44-F47 | 7 de 13 falharam (ENV11 foi artefato de timing) | Pesado empurrado; Root no vento empurrado |
| `server/__AuditSec` + `client/__AuditExploiter` | S0-S8 | F05, F32 | speed hack 87 studs/s aceito | Correção pelo servidor |
| `probes/WindAccumulation` | vento acumulando | F29 | 5 forças, 100 studs/s (config. 20) | 1 força, ~20 studs/s |
| `probes/PlayerForces` | forças no player | F32 | Soft padrão: 0,6 stud (esperado 20) | ~20 studs |
| `probes/DamageStatsAndChainLine` | stats e cadeia em linha | F43, F62 | dano 10 → 10; 51/80 mortos | dano muda pela fórmula; 80/80 |
| `probes/PlayerUlt` + `client/__AuditUltDriver` | ult do player | F19 | 2/3 agarrados, erro 16,9 studs, 2 presos após cancel | 3/3, erro < 2, 0 presos |
| `probes/ManualPossessionSeq` + `client/__AuditDriver` | torre → enxame | F04, F21, F58 | erro em `ControlComponent:76`, rota presa | sequência completa, rota no corpo |
| `client/__AuditClientHooks` | log do cliente | F22, F56, F57 | `suspendNative` true seguido de false | uma mensagem por troca |

Artefatos conhecidos: ENV11 (deriva por granularidade do `task.wait`), K2 crédito de kill
(instável no Caps, confirmado na arena com 45 créditos), E1 enrage (contaminado pelos adds;
use `probes/DamageStatsAndChainLine`), T30 depende da ordem das pastas `Martelo` duplicadas.

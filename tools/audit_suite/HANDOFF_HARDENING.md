# Handoff — Hardening e extensão do motor (Fases 0 a 3)

Você vai continuar o hardening do framework de combate (Roblox/Luau). O lote P0 da auditoria, F05
incluído, está fechado e commitado. O próximo passo é a **Fase 1** do documento de hardening (no
apêndice), mas **só com os itens que continuam abertos**: boa parte dele foi escrita antes do P0 e já
está feita, e algumas premissas estão erradas (ver "Reconciliação").

Reporte ao usuário em português, de forma direta: ele quer críticas, não elogios. **Depois de cada item
concluído, mande o placar de achados abertos** no formato `(0 crít, X alta, X méd, X baixa)`.

## Estado em 16/10/2026

- Branch `audit/suite-p0`, sem push. Commits desde `d6a0fc6`: `88f16ec` (fim de linha LF), `4d5ee9a` (P0
  itens 1 a 4), `b5dc520` F29, `4ecd4c5` F30, `fd93280` F76, `6a246f1` F46, `efac924` F92, `fc4c75a` F05,
  `68b2ec4` (janelas do F05 por ping) e o commit deste handoff.
- **Placar: (0 crít, 13 alta, 33 méd, 16 baixa)**, 62 abertos de 93 achados (`AUDITORIA.md`, F01 a F93).
- Working tree: só o ruído que o usuário mandou deixar fora dos commits, `sourcemap.json` e
  `sync/ReplicatedStorage/Assets/Weapons/Schema/Martelo/WeaponData__14070.luau` (pasta `Martelo` duplicada
  no Studio, F18). Não commite, não apague e não restaure sem perguntar.
- Detalhes do P0 e do F05: [`HANDOFF_P0.md`](HANDOFF_P0.md) e [`HANDOFF_F05.md`](HANDOFF_F05.md).

## Antes de editar

1. Leia `.agents/rules/00` a `03` (20 regras, tratadas como lei). O documento do apêndice renumera as
   regras de 1 a 16; ao citar regra, use a numeração do repositório.
2. Leia a seção "Achados novos" do [`AUDITORIA.md`](AUDITORIA.md) e a reconciliação abaixo.
3. Confira o estado real no git (`git log --oneline -12`, `git status`).

## Como trabalhar

**Sync.** `sync/` é o Script Sync nativo do Studio, **bidirecional**: um `.luau` editado no disco chega ao
Studio em ~2 s (também com o Studio em Play). Depois de editar, compare o hash dos dois lados (FNV-1a de
`Source` sem `\r`). Nunca rode comando git que reescreva arquivo em `sync/` (`stash`, `checkout`,
`reset --hard`): o Studio receberia a mudança. O `.gitattributes` fixa LF, igual ao que o sync grava.

**Commits.** Um por item, com o ID: `fix: [F77] ...` (estilo do repo: `fix:`/`feat:`/`chore:`/`docs:` em
português), terminando com `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Este checkout não tem
identidade do git: `git -c user.name="GabrielFachin" -c user.email="gabrielfachinoliveira@gmail.com" commit`.
Atualize o `AUDITORIA.md` no mesmo commit (`**Corrigido em <data>**: ... Medido: antes → depois`). Sem push
sem pedir.

**Testes no Studio (MCP `rbx-global-mcp-server`).**
- O `execute_luau` roda numa VM separada do jogo. Para rodar na VM do jogo, crie um `Script` com `Source`
  e parent em ServerScriptService (datamodel Server). No cliente, um `LocalScript` em
  `Players.LocalPlayer.PlayerGui` (datamodel Client). Não destrua o Script antes de ele terminar.
- **Pare o Play assim que o teste acabar** (o usuário reclamou do Studio esquecido em Play).
- A `GrandIntegrationDemo` possui o player dos 5 aos 35 s: teste com player depois de t > 38 s e longe da
  origem (800+ studs). Não destrua um chão com o player em cima (ele cai e renasce).
- O place roda com sinais **Deferred** (medido). Os erros de permissão de animação no console já existiam.
- Não há `luau-lsp`, `selene` nem `stylua` instalados: não diga que rodou análise estática.
- Input de player sem teclado (o teclado virtual do Studio é recusado): injete este LocalScript e controle
  pelos atributos `FW_PlayerDir` (Vector3 no mundo) e `FW_PlayerJump` (bool) do ReplicatedStorage, setados
  pelo servidor. O `ControlModule` move o Humanoid e o `InputService` manda o `RequestDir` real.

```lua
-- [FW-DEBUG] driver de input do player
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local plr = game.Players.LocalPlayer
local Controls = require(plr.PlayerScripts:WaitForChild("PlayerModule")):GetControls()
local patched = {}
RunService.RenderStepped:Connect(function()
	local ctrl = Controls.activeController
	if not ctrl or patched[ctrl] then return end
	patched[ctrl] = true
	local getMove, isRel, isJumping = ctrl.GetMoveVector, ctrl.IsMoveVectorCameraRelative, ctrl.GetIsJumping
	ctrl.GetMoveVector = function(self, ...) return RS:GetAttribute("FW_PlayerDir") or getMove(self, ...) end
	ctrl.IsMoveVectorCameraRelative = function(self, ...)
		if RS:GetAttribute("FW_PlayerDir") then return false end
		return isRel(self, ...)
	end
	ctrl.GetIsJumping = function(self, ...) return RS:GetAttribute("FW_PlayerJump") or isJumping(self, ...) end
end)
```

- **Suíte direto do disco**, sem transcrever: `python -I -m http.server 8765 --bind 127.0.0.1` dentro de
  `tools/audit_suite`, `HttpService.HttpEnabled = true` no modo Edit **só com o aval do usuário** (ele deu
  em 16/10 para aquela sessão) e `HttpService:GetAsync("http://127.0.0.1:8765/<arquivo>")` no
  `execute_luau` do servidor. O cliente não faz HTTP: o servidor publica o código num `StringValue` e o
  `execute_luau` do cliente cria o LocalScript. No fim, desligue o `HttpEnabled` e derrube o servidor.
- **Lag simulado:** `settings().Network.IncomingReplicationLag = 0.2` no modo Edit (volte para 0 no fim).
  O `GetNetworkPing` dá 0 no Studio mesmo assim.

**Debug.** Saída de debug/teste com o prefixo `[FW-DEBUG]`; warn estrutural com o prefixo do módulo
(`[AntiCheat]`, `[MovementController]`).

**Placar.** Conte pelo `AUDITORIA.md`, nunca de cabeça:

```python
import re
from collections import Counter
text = open("tools/audit_suite/AUDITORIA.md", encoding="utf-8").read()
seen = {}
for fid, sev in re.findall(r"^\| (F\d{2,3}) \| ([^|]+) \|", text, re.M):
    seen.setdefault(fid, sev.strip())
fixed = {"F01","F02","F03","F04","F06","F07","F08","F09","F13","F14","F20","F21","F22","F23","F24","F39","F54","F58"}  # P0, sem marca na tabela
fixed |= set(re.findall(r"^\| (F\d{2,3}) \|[^\n]*\*\*Corrigido em", text, re.M))
c = Counter(s for f, s in seen.items() if f not in fixed)
print(f"({c['Crítica']} crít, {c['Alta']} alta, {c['Média']} méd, {c['Baixa']} baixa)")
```

## Decisões do usuário (não reabrir sem justificativa técnica nova)

- Possessão em pilha, configurável (Policy Stack/Swap por chamada, por entidade e no padrão do módulo);
  `Possess({ Player })` pausa a IA do alvo e o `Release` restaura; `Possess({ AI, Brain })` troca o Brain.
- F05: modelo B (corpo do cliente, servidor valida e corrige) agora; Server Authority nativo depois, na
  reescrita do movimento (desligar `Movement_Validation_Enabled` em `Physics/Settings`).
- HP 0 não mata o Humanoid nem força respawn, de propósito. As regras de morte do motor ficam em
  `Enum.DeathDefaults`, configuráveis por entidade e sem custo quando desligadas; o F75 (cast de morto)
  entra no mesmo mecanismo.
- **D6 = força Soft aditiva** (confirmado, já aplicado no F46).
- D1 a D5 e D7: o documento marca o padrão `[x]`; só o D6 foi confirmado explicitamente. Siga o padrão
  marcado e registre no relatório, como o próprio documento manda. Se um item tiver impacto grande de
  design (D1 Defense, D4 herança Live), confirme antes com o usuário.
- Commits: 1 por item, sem push. Placar depois de cada item.

## Reconciliação do documento com o código (16/10)

### Fase 0: feita, não repita

| Item | Resultado |
| --- | --- |
| R1 | Nada daquilo existe nem existiu no git. O único presente, `SetControlledEntity(player, id, suspendNative)`, é o conserto do F22. Nada a reverter |
| R2 | 0 colisões entre os 142 métodos expostos por 10 componentes. O erro no boot do F1.12 continua valendo como proteção |
| R3 | Premissa errada. No Studio as duas pastas se chamam `Martelo` (F18: uma com Model, a legada sem). O `martelo` minúsculo só existe no índice do git (o Windows não distingue caixa) e no Model `Workspace.martelo` |
| R4 | Um caso: `ReplicatedStorage/Assets/Weapons/Schema/Martelo/WeaponData.luau` faz `require` de `ServerStorage.DataBase.SkillDatabase` |
| R5 | `SetActionState`: Dash:38, M1:22/59, Ultimate:29, WeaponTransform:18. `RemoveActionState`: Dash:25, M1:37/73, Ultimate:91, WeaponTransform:40. `ApplyLoadout`: CombatComponent:621, WeaponTransform:48. `StartHitbox`: M1:30/65, Ultimate:31. `Add/RemoveHitboxOwner`: só SkillRunner:181/409. `.TakeDamage(` fora do Health: CombatComponent:649, GrandIntegrationDemo:84, Skill2:12, Bleed:42. `.Heal(`: Dash:95. `ApplyStatus` posicional: Dash:39, M1:21/58, Ultimate:27, WeaponTransform:17, Main:89/107 (quebrados, F93). `ClearAll`: só StatusComponent:828. `PlayAnimation/StopAnimation/OnMarker`: M1 e WeaponTransform:27. `SetChosenChar`/`GetSkill*`/`LoadSkillsData`: só dentro do Combat. `.SetEnabled(`: ControlComponent (5x), GrandIntegrationDemo:205/239. `rootOrigin`/`Lineage.Root`/`Depth`: só SkillRunner:147/149 e Types:40, e ninguém consome |
| R6 | `ServerStorage.Modules.CharData` só tem `!Doc`: `_LoadFolders`/`LoadSkillsData`/`GetSkill*` são caminho morto; o `CharacterDatabase` é a fonte viva. `_ApplyStats` lê `JumpPower` (o DB usa `JumpForce`), e o `Speed` da forma é sobrescrito todo frame pelo `MovementController` |
| R7 | `Workspace.Script` existe e cria um bloco amarelo de tamanho aleatório na origem a cada boot. DOC duplicado e idêntico (F69) |

### Fase 1: o que falta

| Item | Estado | O que fazer |
| --- | --- | --- |
| F1.1 | Feito (F13) | Nada. O `TriggerSet:Emit` protege cada listener com `xpcall` |
| F1.2 | Parcial (F14) | Devolver o cooldown quando o `onStart` falha (`SkillHandler.luau:172-186`) |
| F1.3 | Aberto | Guarda de `IsEnded()` em `Recast` e `TriggerAction` (o handler já filtra com `liveRunners`) |
| F1.4 | Aberto | Limpar o ActionState do runner no teardown do `endSkill`; o `warn("Skill não pode rodar!")` do `TrySelfCancel` está sem prefixo |
| F1.5 | Aberto | `AddActiveSkill`/`AddHitboxOwner` só para `Types.Skill`. Nenhum status usa `onHit` hoje |
| F1.6 | Aberto | Tirar o `BuildHistory` lixo do `SkillHandler.activate` e passar `nil` (ninguém consome `depth`/`rootOrigin`) |
| F1.7 | Parcial (F09) | Clonar o `opts` antes de setar `Source` (`SkillRunner.luau:353-358`) |
| F1.8 | Aberto (= F77 + D5) | ID existente no restack, renovar no máximo, `Duration` da reaplicação, campo `counter` morto |
| F1.9 | Feito (F08) | Nada |
| F1.10 | Parcial (F87) | F84 (`StatusController` morto) e tirar a tabela `defaults` de dentro do `GetStatus` |
| F1.11 | Aberto, confirmado | Place Deferred: o `Stopped` da track velha apaga a nova (`AnimationComponent.luau:215-217`); conexões vazando; `LoadAnimation` a cada play; o M1 para com a key crua |
| F1.12 | Aberto | API sobrevive a `RemoveComponent`/`Destroy`; `Destroy` por `pairs` e sem `OnRemoved`. A demo faz `RemoveComponent(AI)` (linha 241) |
| F1.13 | Aberto | NPC com Model destruído fica no mapa; `Remove` só aceita Instance; `Get` dá warn em raycast |
| F1.14 | Aberto | `SetChosenChar` chama `SetAttribute`, que não existe; caminho de pastas morto (R6); stats da forma ignorados |
| F1.15 | Aberto (= F81) | `runtimeDuration = TransformTime` no `onStart` |
| F1.16 | Aberto (= R4 + F18) | `WeaponDatabase` no ServerStorage. Pergunte ao usuário antes de apagar a `Martelo` duplicada |
| F1.17 | (a) e (b) feitos | Falta tirar o `hunter.SetEnabled` da demo (linhas 205/239). **Não** aplicar o (c): o Brain é funcional desde o F24; `By` fica para o F2.6 |
| F1.18 | Feito (F29, F76, F46) | Nada |
| F1.19 | Aberto (parte do F19) | Feed-forward no `FollowTarget` (velocidade do líder + correção limitada). Prova: U2 U1 (hoje 10,9 studs de erro no grab) |
| F1.20 | Junto de cada item | Um `TestHarness.Run` por item em `IntegrationTests.server.luau` |

Ordem sugerida, das baratas para as que mexem em mais lugares: F1.3, F1.7, F1.2, F1.4 + F1.5, F1.6, F1.8,
F1.10, F1.15, F1.17, F1.11, F1.12, F1.13, F1.14, F1.16, F1.19. Ao fim da Fase 1, relatório e **parada**,
como o documento manda.

As Fases 2 e 3 não começaram. Várias falhas abertas da auditoria (lote P1) caem dentro delas: F79 (hitbox
compartilhada) é o F2.4, F12/F16 (cooldown e loadout) são o F2.1 e o F2.2, F10/F11 (dano e escudos) são o
F2.7, e F31/F32/F33 (forças por massa) seguem soltas, sem item no documento.

### Linhas de base para regressão (16/10)

BatchA 11/22, BatchB 5/12, BatchP 7/8 (P4 = F31), U2 com U2 e U3 passando (U1 = F19, P4b = F31),
IntegrationTests 7/7, `ManualPossessionSeq` inteira, Env 9/13 (ENV1/ENV8 = F33, ENV4, ENV5),
`__AuditSec` S1 34 studs / S2 revertido / S3 5,6 / S4 4,7 / S8 0 correções. Com 200 ms de lag e ping
emulado, 0 correções em jogo legítimo.

## Observações para o usuário decidir

- `sourcemap.json` e a duplicata do Martelo (F18) fora dos commits.
- Três Models chamados `NAO APAGA` no Workspace (regra 19: nome duplicado). Parecem intencionais.
- `Workspace.Script` (R7) e os comandos de chat do `Main` (F93).

---

## Apêndice: documento original (texto do usuário, 16/10/2026)

> Gerado em outro chat por leitura estática de um snapshot anterior ao P0. Leia a reconciliação acima
> antes de seguir qualquer item. Onde ele diz "Rojo" e "você não tem Studio", aqui é o Script Sync nativo
> e há MCP do Studio.

TAREFA — Hardening e extensão do motor de combate (Roblox/Luau, Rojo)

Este documento foi gerado a partir de LEITURA ESTÁTICA de um snapshot do código (nada foi executado). O repositório pode ter mudado desde então. Confirme cada causa-raiz no código antes de corrigir. Se uma afirmação daqui estiver errada, diga isso no relatório e NÃO "conserte" o que não está quebrado.

### 0. Como trabalhar (leia inteiro antes de começar)

Contexto. Dev solo. Framework de combate genérico (não é um jogo), código em `sync/`, sincronizado com Rojo. Você NÃO tem Roblox Studio e não consegue executar nada. Testes de integração são escritos em `sync/ServerScriptService/Scripts/Tests/` usando o `TestHarness` existente; o dev roda no Studio. Se `luau-lsp`, `selene` ou `stylua` estiverem instalados, rode análise estática nos arquivos tocados. Se não estiverem, não finja que rodou.

Objetivo do motor. Qualquer personagem ou sistema complexo tem que ser implementável SEM editar o motor: só adicionando skills, status, componentes novos, entradas em Enum/Databases e módulos utilitários (os "pontos de expansão"). Sempre que um cenário exigir editar `SkillRunner`, `SkillHandler`, `SkillScheduler`, `EntityCore`, `DataManager`, os componentes core, `TriggerSet`, `StateTable/Helper` etc., isso é um GAP do motor.

Regras do projeto (resumo — tratar como lei):

1. DRY religioso: a mesma ação nunca implementada em 2 lugares.
2. Framework completo: abstrair tudo que reduz o código do usuário final (helpers, enums, dados reutilizáveis).
3. Agnóstico de gênero (MOBA, fighter, battleground, cartas, roguelike); suportar interações absurdas e cíclicas sem crash; não pressupor mecânicas.
4. O único pressuposto são "skills": regras por momento de ciclo de vida (skill, buff, debuff, on-hit, minion herdando efeitos do pai etc.).
5. Tudo que interage é entidade; entidade simples = poucos componentes = barata.
6. Otimizado por padrão; o custo deve ser proporcional ao jogo, não ao framework.
7. Player e inimigo são iguais perante o framework (possessão, roubo de skills, herança de cooldowns, mesmo "contexto").
8. Autoridade no servidor, com espaço pra ownership customizado no futuro.
9. Facilitar client-server (VFX, som, replicação prontos).
10. Nada de string mágica / valor solto: tudo centralizado (Enum, Database).
11. Módulos "burros" e agnósticos sempre que possível.
12. Dependência entre componentes explícita (`Requires`, assert ou comentário no cabeçalho).
13. Shape de dado compartilhado tem dono único (tipo/comentário num lugar só); ninguém lê por convenção própria.
14. Debug output identificável e removível em bloco (prefixo `[FW-DEBUG]`), nunca `print` cru misturado com os warns estruturais.
15. Nomes duplicados ou que diferem só por maiúscula/minúscula = bug.
16. Componentes auto-suficientes; dependência só quando estruturalmente inevitável, e declarada.

Modo de trabalho.

- Fases com PARADA obrigatória. No fim de cada fase entregue: itens feitos (IDs), arquivos tocados, decisões tomadas, riscos, e o que o dev precisa testar no Studio. Não avance sem resposta do dev.
- 1 commit por item, com o ID na mensagem (`[F1.3] Recast ignora runner encerrado`). Não reformate código não relacionado. Comentários em PT-BR, no estilo do repositório.
- Mantenha compatibilidade de chamadas antigas quando for barato (ex: assinatura posicional de `ApplyStatus`). Quando não for, liste todos os call-sites migrados.
- Itens que dependem de uma decisão (seção 1) seguem a opção marcada. Se a seção 1 estiver sem marcação, use o default indicado e registre isso no relatório.
- Se um item conflitar com outro ou com o código real, pare naquele item, explique, e siga com os independentes.
- As specs abaixo SUBSTITUEM qualquer design anterior produzido por outra IA (ver R1).

### 1. Decisões (o dev marca antes de rodar; `[x]` = default recomendado)

- D1 — Semântica de `Defense`. `[x]` Percentual com retorno decrescente: `dano *= 100 / (100 + Def)`; Def negativa amplifica: `dano *= 2 - 100 / (100 - Def)`. Trait nova `TrueDamage` ignora. `[ ]` Flat (`dano - Def`, mínimo 0). Motivo do default: DOT de 1 de dano por tick (ex: `Bleed`) e builds de muitos hits pequenos morrem com Defense flat.
- D2 — Efeitos (`context.effects`) em hit totalmente bloqueado. `[x]` Não aplica, exceto se o ataque tiver a trait `ApplyOnBlock`. `[ ]` Aplica sempre (comportamento atual).
- D3 — Eventos OUT de dano indireto (DOT, reflexo, área de status). `[x]` Emite OUT no dono do efeito (via `Attribution`), com as traits do efeito no contexto (listeners filtram com `None = {DOT}` quando não quiserem). `[ ]` Não emite OUT pra dano indireto.
- D4 — Herança de reações (TriggerSet) pra entidades filhas. `[ ]` Snapshot (Fork atual) + vida atrelada ao dono (mínimo). `[x]` Live: o filho consulta reações herdáveis dos ancestrais no `Emit`; Fork vira opt-in (`Inherit.Mode = "Snapshot"`).
- D5 — `stackOnSelf` quando já está no máximo de stacks. `[x]` Renova a duração (opt-out com `data.refreshOnMax = false`). `[ ]` Não renova (atual).
- D6 — Forças Soft. `[x]` Aditivas: alvo do eixo = locomoção pretendida no eixo + soma das forças soft. `[ ]` Alvo absoluto (atual), só corrigindo o `MaxForce`.
- D7 — Redução de cooldown. `[x]` Stat `CooldownHaste` com retorno decrescente: `cd *= 100 / (100 + Haste)` (100 de Haste = metade do CD; nunca chega a 0). `[ ]` `CooldownReduction` percentual somado, com teto (ex: 40%). Motivo do default: percentual somado chega em 100% (CD zero) em builds de roguelike com cartas empilhadas; o teto vira regra especial em todo lugar. Haste escala linear em "casts por minuto", igual à Defense do D1.

### FASE 0 — Reconhecimento (NÃO editar nada)

R1. Verifique se existem restos de uma tentativa anterior (feita por outra IA) de aplicar: `interruptBy`, `ForceCancelActionState`, `DamageScale.luau`, `data.damageScale`, `context.baseDamage`, Loadout aplicado dentro do `EquipWeapon`, `softBudget` no `MovementController`, feed-forward no `FollowTarget`, `SetControlledEntity(player, id, suspend)`. Use `git log`, `git diff` e grep. Relate o que existe e em que estado. Qualquer coisa parcial: proponha reverter ou completar seguindo as specs deste documento.

R2. Colisões de API: liste todo nome de método presente em mais de um `ExposeAPI` dos componentes em `sync/ServerScriptService/EntityData/Components/`. Hoje `EntityCore:AddComponent` sobrescreve em silêncio. Nomes genéricos como `SetEnabled` (AIComponent) são suspeitos; `ControlComponent` depende dele.

R3. Regra 19: nomes que diferem só por caixa. Caso conhecido: pasta `sync/ReplicatedStorage/Assets/Weapons/Schema/martelo` vs `Weapon = "Martelo"` em `DataBase/CharacterDatabase/Schema/Base.luau` e `BaseName = "Martelo"` no `WeaponData`. Confirme se `EquipWeapon("Martelo")` encontra a pasta (`FindFirstChild` é case-sensitive).

R4. `ModuleScript` em `ReplicatedStorage` que faz `require` de algo em `ServerStorage`. Caso conhecido: `ReplicatedStorage/Assets/Weapons/Schema/martelo/WeaponData.luau` requer `ServerStorage.DataBase.SkillDatabase`. Liste todos.

R5. Call-sites (arquivo:linha) de: `SetActionState`, `RemoveActionState`, `ApplyLoadout`/`_ApplyLoadout`, `StartHitbox`, `AddHitboxOwner`, `.TakeDamage(` chamado fora do `HealthComponent`, `.Heal(`, `ApplyStatus(` na forma posicional, `ClearAll`, `PlayAnimation`/`StopAnimation`/`OnMarker`, `SetChosenChar`, `GetSkillName`/`GetSkillScript`/`GetSkillData`/`LoadSkillsData`, `self.Entity.SetEnabled`, `rootOrigin`/`Lineage.Root`/`Lineage.Depth`.

R6. Duas fontes de dado de personagem? `CharacterDatabase` (usado por `CombatComponent:SetCharMode`) vs pasta `ServerStorage.Modules.CharData` (usada por `_LoadFolders`/`LoadSkillsData`/`GetSkill*`). Diga qual está viva. Também: `_ApplyStats` lê `stats.JumpPower`, mas `CharacterDatabase/Schema/Base.luau` declara `JumpForce`, e `AttributesComponent:OnAdded` lê via `Enum.Stats` (regra 17).

R7. Arquivos soltos/duplicados: `sync/Workspace/Script.server.luau` (spawna dummy aleatório a cada boot), `ServerStorage/!DOC/DOC.luau` duplicado em `ServerStorage/Modules/CharData/!Doc/DOC.luau`.

Entregue o relatório da Fase 0 e PARE.

### FASE 1 — Bugs de robustez e ciclo de vida (sem API nova relevante)

**F1.1 — `SkillRunner:endSkill` não é exception-safe.** Arquivo: `sync/ServerScriptService/Modules/SkillRunner.luau`. `_fire("onEnd")` não é protegido. Se o `onEnd` da skill der erro, nada depois roda: `RemoveActiveSkill`, `RemoveHitboxOwner`, `Emit(OUT.onEnd)`, `Unregister`, `onFinish`. Como `state` já virou `Ended`, o `runner:endSkill(true)` chamado pelo catch do `SkillScheduler` retorna na hora. Efeitos: a skill fica em `ActiveSkills` pra sempre (com `maxInstances = 1` o handler entra no caminho de recast/cancel de um runner morto); um Status nunca chama `onFinish` e a entrada fica no `StatusComponent` (ex: Stun eterno). Spec: `onEnd` em `pcall` (warn com `skillName`); o teardown inteiro sempre roda; cada `Emit` do teardown também não pode abortar o resto. Teste: skill cujo `onEnd` faz `error()` → depois disso `GetActiveSkills(nome)` vazio; status com `onEnd` que dá erro é removido e suas tags somem.

**F1.2 — `onStart` sem proteção.** `start()` registra no scheduler, faz `AddActiveSkill` e `AddHitboxOwner`, e só então chama `onStart` sem pcall. Um erro sobe pro `SkillHandler`/`InputValidator` com o runner já registrado (às vezes já com ActionState setado). Spec: `start()` retorna boolean; em erro → warn + `endSkill(true)` + `return false`. `SkillHandler.activate` trata o `false`: não chama `track`, devolve o cooldown (`ResetCooldown`) e retorna false.

**F1.3 — `Recast`/`Release`/`TriggerAction` em runner encerrado.** `Recast(checkOnly)` responde `true` mesmo com `state == Ended`. Spec: os três retornam false/nil se `IsEnded()`.

**F1.4 — ActionState não é liberado quando o runner termina.** `CombatComponent.ActionState` só é limpo se a skill chamar `RemoveActionState` manualmente (padrão `self.cleanUp`). Se a skill esquecer, ou der erro antes, um ActionState da categoria Out fica apontando pra runner morto e `TrySelfCancel` bloqueia TODA skill nova daquela entidade pra sempre. Spec: no teardown do `endSkill`, se a entidade tem Combat, chamar `RemoveActionState(self)` (já filtra por runner e é idempotente). Não remova as chamadas manuais existentes nesta fase.

**F1.5 — Todo runner vira "skill ativa" e dono de hitbox.** `start()` faz `AddActiveSkill` e `AddHitboxOwner` pra QUALQUER tipo de runner, inclusive Status. Consequências: (a) um Status com o mesmo nome de uma skill (ex: skill "Roleta" que aplica em si o status "Roleta") aparece em `GetActiveSkills("Roleta")` e o `SkillHandler` acha que a skill já está ativa; (b) um Status no portador recebe `onHit` de todo golpe da arma dele. Spec: `AddActiveSkill`/`RemoveActiveSkill` só para `Types.Skill`. Nesta fase, restrinja `AddHitboxOwner` a `Types.Skill` também (o modelo definitivo é o F2.4).

**F1.6 — Lineage nasce com raiz lixo.** `SkillHandler.activate` monta `ChainHistory = StateTable.BuildHistory({ rootOrigin = ..., rootSkill = ..., history = ..., depth = ..., chainStart = ... })`, mas `Helper.BuildHistory` lê `ParentLineage`, `Entity` e `name`. Resultado: um nó raiz com `Origin = nil` e `Cause = "Unknown"`; `Lineage.Root.Origin` (e o `context.rootOrigin` do `SkillRunner:BuildContext`) é sempre nil, e `Depth` começa em 2. O `if not skill.data.ChainHistory` é código morto. Spec: remover o bloco e passar `nil` como lineage pro `SkillRunner.new`. Use o resultado da R5 e ajuste consumidores que dependessem do off-by-one.

**F1.7 — `SkillRunner:ApplyStatus` passa parâmetros errados e muta o `opts` do chamador.** Hoje: `target.ApplyStatus(statusData, opts.Duration, opts.Source, opts)` cai no caminho posicional legado, e o 4º parâmetro (`ID`) recebe a tabela `opts` inteira: o ID do status vira uma tabela e `opts.ID` é ignorado. Além disso, `opts.Source = opts.Source or self` muta a tabela do chamador: se uma skill usar um `opts` constante de módulo (`local OPTS = { Duration = 2 }`), o primeiro runner vira Source eterno pra todos os jogadores. Spec: `local o = table.clone(opts or {})`, `o.Source = o.Source or self`, `target.ApplyStatus(statusData, o)`. O campo `Target` dentro de `_ApplyStatusInner` usa `target.Entity`, que num EntityCore é sempre nil (campo morto/confuso): documente ou remova.

**F1.8 — `stackOnSelf`: ID retornado errado e sem renovação no máximo.** `StatusComponent:_ApplyStatusInner`, ramo "STACK NA MESMA INSTÂNCIA": (a) retorna o `suppliedID` recém-gerado, não `existing.ID` → `RemoveStatusByID` com o ID devolvido falha do 2º stack em diante; (b) no máximo de stacks retorna sem zerar `elapsedTime` (ver D5); (c) `Duration` de uma reaplicação é ignorada; (d) o campo `counter = 1` gravado na entrada nunca é atualizado (o valor real é `runner.skill.counter`) — remova o campo morto (regra 17). Spec: retornar `existing.ID`; renovar no máximo por padrão (`data.refreshOnMax ~= false`); se vier `Duration`, `existing.runner.skill.runtimeDuration = Duration`. Não trocar `Source` no restack (documentar: o crédito fica com quem aplicou o 1º stack).

**F1.9 — `ClearAll` modifica a tabela durante `pairs`.** `ClearAll` itera `pairs(group)` chamando `RemoveStatus`, que dispara o `onCancel` de cada status. Um `onCancel` que aplica outro status (cadeia "ao ser purificado, aplica X") insere chave nova durante a travessia (comportamento indefinido em Luau). Spec: snapshot dos nomes antes de remover; o retorno conta instâncias, não nomes.

**F1.10 — `SkillFactory.GetStatus` engole argumentos.** Os wrappers `onEnd`/`onCancel` chamam o callback original só com `selfRunner` (o `context` some). Spec: repassar `...`. Manter e DOCUMENTAR que Status não pode recusar cancel (se um dia puder, `RemoveStatus` precisa respeitar: hoje ele apaga a entrada mesmo se o runner continuar vivo). Remover `StatusController`/`RemoveById` se o grep confirmar que é morto. Tirar a tabela `defaults` de dentro da função (é recriada a cada `ApplyStatus`).

**F1.11 — `AnimationComponent`: race no `Stopped`, vazamento de conexões, `LoadAnimation` a cada play.** (a) `PlayAnimation` conecta `track.Stopped` que faz `self.Tracks[key] = nil`. Se a mesma key tocar de novo (spam de M1, cancel de AA), o `Stopped` da track ANTIGA pode rodar depois da nova já estar salva (com `Workspace.SignalBehavior = Deferred`, que é o padrão de templates novos e vai virar o Default) e apaga a referência da track NOVA: `StopAnimation(key)` deixa de parar a animação que está tocando. Spec: `if self.Tracks[key] == track then self.Tracks[key] = nil end`. (b) Toda conexão vai pra `self._connections` e só sai no `Destroy` (1 por play + 1 por `OnMarker`). Spec: `Stopped` com `:Once` e sem guardar; `OnMarker` devolve a conexão e a registra num conjunto removível (o runner vai desconectar via F2.15). (c) `LoadAnimation` a cada play. Spec: cache de track por `animId`; se a track cacheada estiver tocando sob outra key, carregar uma nova. (Existe limite de tracks carregadas por Animator.) (d) Spec: normalizar a chave em UMA função (`keyOf`) usada por Play/Stop/OnMarker/GetTrack/IsPlaying. Hoje `PlayAnimation` guarda `tostring(animId)` e `M1.luau` chama `StopAnimation(self.M1Start)` com o valor cru.

**F1.12 — `EntityCore`: API de componente sobrevive a Remove/Destroy; colisão silenciosa.** `AddComponent` instala closures em `self[method]`. `RemoveComponent` e `Destroy` nunca as removem: depois de remover um componente, `entity.Metodo()` chama o componente destruído (`self.Entity == nil` → erro) em vez de cair no stub. Spec:

- Guardar `self._apiOwner[method] = componentName`; `RemoveComponent` e `Destroy` fazem `self[method] = nil` (volta pro stub via `__index`).
- Colisão: no auto-registro, dois componentes expondo o mesmo nome → `error` no boot listando ambos. Resolva as colisões da R2 renomeando (ex: `AIComponent.SetEnabled` → `SetAIEnabled`, atualizando `ControlComponent`).
- `Destroy` determinístico: ordem inversa da inicialização (Normal, depois High), chamando `OnRemoved` antes de `Destroy` (hoje `Destroy` pula `OnRemoved` e usa ordem de `pairs`).
- Depois de `Destroy`, `Listen`/`Emit` viram no-op (`if not self.Active then return end`). Não descarte `_triggerSet` se D4 = Live (filhos podem consultar); só marque inativo.

**F1.13 — `DataManager`: zumbis e vazamento.**

- NPC cujo `Model` é destruído continua no mapa e no `MovementController`. Spec: em `Create`, `Model.Destroying:Once(...)` → remove a entidade (idempotente).
- `EntityCore:Destroy()` chamado direto não tira do mapa. Spec: o DataManager é o dono do ciclo de vida; injete no core um callback `_onDestroyed` (evita require circular) que limpa o mapa.
- `Remove` aceita EntityCore, ID ou Instance.
- `GetEntityFromInstance` usa lookup silencioso (hoje `Get` dá warn a cada raycast num modelo com ID velho).

**F1.14 — `CombatComponent`: stats de forma ignorados e `SetChosenChar` quebrado.**

- `_ApplyStats` chama `SetSpeed`/`SetJumpForce` do Movement, mas o `MovementController` sobrescreve todo frame com `GetStat` do Attributes: Speed/JumpForce da forma não têm efeito. E lê `stats.JumpPower` enquanto o DB usa `JumpForce`. Spec: com Attributes, `SetStat` pra cada chave de `Enum.Stats` presente em `formData.Stats` (chaves SEMPRE via Enum); sem Attributes, manter o fallback atual. MaxHP continua pelo `SetMaxHP` (preserva a proporção).
- `SetChosenChar` chama `self.Entity.SetAttribute(...)`, que nenhum componente expõe → erro em runtime. Spec: `SetChosenChar(char)` = `SetCharMode(char, self.Mode)` (um caminho só). Sobre o caminho legado de pastas (`_LoadFolders`/`LoadSkillsData`/`GetSkill*`): use a R6; se estiver morto, remova; se estiver vivo, relate antes de mexer.

**F1.15 — `WeaponTransform.luau`: `TransformTime` ignorado.** `data.duration = 0` → o runner termina no 1º Heartbeat; `onEnd` troca o modo e o `cleanUp` remove o `NoControl` na hora. Spec (mínimo nesta fase): em `onStart`, `self.Runner.skill.runtimeDuration = nextModeData.TransformTime or 0`. A troca de Loadout dele (que hoje APAGA o loadout inteiro) é tratada em F2.1.

**F1.16 — Dado de arma em ReplicatedStorage requer ServerStorage.** Com base na R4: `WeaponData` (que referencia `SkillDatabase.Keys`) não pode viver em `ReplicatedStorage`. Spec: mover os dados de arma pra `ServerStorage/DataBase/WeaponDatabase` (registry global por nome, no mesmo padrão do `SkillDatabase`), deixando em `ReplicatedStorage` só os modelos. Corrigir a caixa `martelo`/`Martelo` (R3). O desacoplamento completo está em F2.16.

**F1.17 — Possessão: notificação em 2 eventos e IA nativa não suspensa.** (a) `ControlComponent:Possess` chama `AntiCheat.SetNativeControlSuspended(player, true)` (FireClient com o ID ANTIGO e `suspendNative = true`) e depois `SetControlledEntity(player, id)` (outro FireClient com `suspendNative = false`): o 2º evento desfaz o 1º, e pulo/WASD nativos voltam a agir no corpo antigo. Spec: um único `AntiCheat.SetControlledEntity(player, entityID, { SuspendNative = bool })` → um FireClient. O mesmo em `Release`. Atualize o LocalScript que escuta `ControlStateChanged`. (b) `Possess` corta o input do Player nativo, mas NÃO desliga o Brain de uma IA nativa: jogador possuindo NPC (ou boss possuindo minion) disputa com o Brain do próprio corpo. A `GrandIntegrationDemo` faz `hunter.SetEnabled(false)` na mão, o que prova o gap. Spec: se o controlador nativo é IA e a entidade tem AI, `Possess` guarda o estado e desliga; `Release` restaura. Remova o workaround da demo. (c) `Controller.Brain` é campo morto (nada o executa). Spec: remover do tipo; adicionar `By: EntityCore?` (quem está possuindo, pra atribuição e consulta). Documentar o padrão "boss possui minion": `minion.Possess({ AI = true, By = boss })`, e o Brain do boss emite `SkillHandler.HandleIntent(minion.ID, ...)`. (d) Só registrar no relatório (não mover agora): o roteamento de controle mora no `GlobalAntiCheat` (responsabilidade misturada).

**F1.18 — Forças Soft (ventilador fraco + empilhamento + perda de controle).** Arquivos: `Modules/Physics/MovementController.luau`, `EntityData/Components/MovementComponent.luau`, `ServerStorage/Modules/Combat/AreaEffect.luau`, `.../AreaBehaviors.luau`. (a) `budget` é calculado, mas o fechamento do frame usa sempre `Settings.Soft_Force_Strength`: o `MaxForce` pedido é ignorado. (b) Forças Soft SOMAM velocidade (`softAccum += ...`). `AreaEffect:OnStay` (poll de 10 Hz) cria uma força nova de 0.5 s a cada tick → ~5 simultâneas → 5x a velocidade pedida. Corrigir só o (a) AMPLIFICA o (b). Não é inofensivo. (c) O alvo Soft é ABSOLUTO no eixo reivindicado: com MaxForce alto o jogador perde a locomoção naquele eixo (não consegue andar contra o vento). Esse é o motivo real do trade-off "fraco vs. rouba controle". Spec: `AddForce` aceita `Key`: se existe força ativa com a mesma `Key`, renova (`ElapsedTime = 0`, troca `Data`) e devolve o mesmo ID. `AreaBehaviors.DirectionalForce` usa `Key = forceType .. ":" .. areaId` (AreaEffect ganha um id único). Budget soft por eixo = `max` dos `MaxForce` das soft ativas (default: Settings). Se D6 = aditivo: alvo do eixo = locomoção pretendida no eixo (`Direction * GetSpeed()` quando `canMove`, senão 0) `+ softAccum`. Teste com `Scripts/Tests/VentiladorDemo.server.luau`: parado na zona a velocidade estabiliza (não cresce); andando contra o vento o personagem avança mais devagar, mas avança.

**F1.19 — `FollowTarget` com erro estacionário.** O controlador é só proporcional; com `FollowMaxSpeed <= velocidade do líder` o erro satura e para de fechar. Spec: `vel = velLider + clampMagnitude(erro * FollowResponsiveness, FollowMaxSpeed)` — o clamp vale SÓ pro termo de correção. Se clampar o total no `FollowMaxSpeed`, o feed-forward consome o orçamento e o erro volta a não fechar. `velLider` = `AssemblyLinearVelocity` do anchor. Em `Ultimate.luau`, `FollowMaxSpeed` passa a significar margem de correção. Observação (não mudar sem o dev confirmar): `GrabOffset (0, 0, -4)` em espaço local fica NA FRENTE do caster (em Roblox, -Z é o LookVector).

**F1.20 — Testes da Fase 1.** Em `IntegrationTests.server.luau`, um `TestHarness.Run` por item quando fizer sentido:

- `onEnd` com erro não deixa zumbi (skill e status);
- `onStart` com erro devolve o cooldown e não deixa ActionState;
- ActionState Out é liberado quando a skill termina sem chamar `RemoveActionState`;
- Status homônimo de uma skill não bloqueia a skill;
- `ApplyStatus` via runner retorna ID string, e `RemoveStatusByID` com ele funciona; `opts` do chamador não é mutado;
- stack no máximo renova a duração; o ID do restack é o existente;
- `ClearAll` com `onCancel` que aplica outro status não quebra;
- `RemoveComponent` → o método vira stub (warn, sem erro);
- re-play na mesma key de animação mantém `IsPlaying(key) == true` (se o dummy de teste não tiver Animator, documente como teste manual);
- força Soft com `Key` não empilha.

PARE. Relatório da Fase 1.

### FASE 2 — Gaps estruturais (API nova; cada item deixa um ponto de expansão no lugar de uma edição futura do motor)

Ordem sugerida: F2.1 → F2.2 → F2.3 → F2.4 → F2.5/F2.6/F2.7 (juntos) → F2.8 → F2.9 → F2.10 → F2.11 → F2.12 → F2.13 → F2.14 → F2.15 → F2.16 → F2.17 → F2.18. Chaves novas SEMPRE em `StateTable/Enum` (regra 12); todo shape novo ganha tipo em `Types.luau` (regra 17).

**F2.1 — Loadout em camadas.** Problema: `CombatComponent:_ApplyLoadout` faz `table.clear(self.Loadout)`. Forma, modo de arma e troca manual escrevem a MESMA tabela: um modo que só declara `Ability1` apaga M1/Dash/Ultimate (é o que o `WeaponTransform` faz hoje com o `WeaponData` do Martelo). Spec:

- `Enum.LoadoutLayers = { Form = 0, WeaponMode = 10, Manual = 20, Temporary = 30, Override = 40 }`.
- Combat guarda `_layers[layer] = { [slot] = skillKey | false }`. Loadout efetivo: por slot, vale a camada de maior prioridade que declara o slot; `false` BLOQUEIA o slot (forma sem Ultimate, silence de um slot só). Efetivo é cacheado e recalculado só quando uma camada muda.
- API: `SetLoadoutLayer(layer, map, owner?)`, `ClearLoadoutLayer(layer, owner?)`, `SetLoadoutSlot(layer, slot, key|false|nil, owner?)`, `GetLoadout()` (efetivo), `GetLoadoutSource(slot)` (qual camada venceu). `owner` = runner: quando o runner termina, as entradas dele somem (via F2.15).
- Fachadas de compatibilidade: `SetCharMode` → camada `Form`; `WeaponComponent:SetMode` → camada `WeaponMode` (só se o modo declarar loadout); `ApplyLoadout(map)` → `Manual` (warn de depreciação); `EquipSkill(slot, key)` → `SetLoadoutSlot(Manual, ...)`.
- Toda mudança do efetivo emite `LoadoutChanged` (F2.12). Teste: forma declara M1/Q/W/E/R/Dash, modo de arma declara só Q → Q vem do modo e o resto da forma; `false` na Temporary bloqueia o slot; runner dono termina → camada dele some.

**F2.2 — Recast antes do cooldown, início do cooldown, cargas, grupos, falha sem custo.** Problema: `SkillHandler.activate` checa `HasCooldown` ANTES do caminho de recast, e o recast reinicia o cooldown. Skill de 3 recasts (Riven Q) é impossível; combo M1 só continua depois do CD. Spec:

- Ordem no `activate`: runner vivo da skill (respeitando `maxInstances`) com `Recast(true)` → recast, SEM checar nem setar cooldown. Senão → checagem de cooldown → cast novo.
- `data.cooldownStart = Enum.CooldownStart.OnCast | OnEnd | Manual` (default `OnCast` = comportamento atual). `OnEnd` aplica no teardown do `endSkill` (inclusive cancel, salvo `data.cooldownOnCancel == false`). `Manual`: a skill chama `runner:StartCooldown(seconds?)`.
- `data.charges = { Max = n, Recharge = s }` opcional: o sistema de cooldown guarda cargas; cast gasta 1; recarga uma por vez. `GetCharges(key)`. Sem isso cada skill de carga reimplementa timer (violação de DRY).
- `data.cooldownGroup` opcional: cooldown indexado pelo grupo em vez do nome (skills compostas/roubadas que dividem um CD; F3/T2 depende disso).
- `runner:Fail(reason)`: encerra com `EndReason.Failed` e DEVOLVE o cooldown/carga gastos no cast. Caso de uso: dash que exige alvo e não achou.
- `ReduceCooldown(key, seconds)`, `ResetCooldown(key)` passam pelo mesmo caminho e emitem `CooldownChanged` (F2.12). O CD final passa pelo `CooldownHaste` (D7, F2.13). Teste: 3 recasts dentro da janela sem cooldown entre eles, CD começa no fim; `Fail` devolve carga; duas skills no mesmo grupo compartilham CD.

**F2.3 — Política de interrupção (substitui a whitelist por nome do plano antigo).** Problema: `TrySelfCancel` só conhece a categoria Self; qualquer Out ativo bloqueia toda skill nova. Whitelist por NOME não funciona com skill composta/roubada/criada em runtime. E CC (Stun) não interrompe skill em andamento. Spec:

- `SetActionState(state, runner, policy?)`, `policy = { InterruptBy = TraitQuery?, CancelableAfter = number? }` guardada na instância (a definição do ActionState continua congelada).
- Semântica: Self = minhas skills novas cancelam se casarem `InterruptBy` (nil = qualquer uma) e já passou `CancelableAfter`; Out = só interrupção externa ou `InterruptBy` explícito; Locked = nada, exceto `ForceCancelActionState`.
- `TrySelfCancel(incomingSkill)` recebe a skill que chega e testa as traits dela contra a política. `runner:SetInterruptPolicy(policy)` troca a política no meio da execução (ex: abrir a janela de cancel no marker `Hit`).
- Trait nova `AACancel` (skills que cancelam ataque básico).
- `data.interrupts = true` num Status (Stun, Congelado): ao aplicar, chama `Combat:Interrupt(sourceRunner)`, que cancela o runner do ActionState atual (se não for Locked) e toda skill ativa sem a trait `Uninterruptible`, com `EndReason.Interrupted`. Teste: M1 com `{ InterruptBy = { Any = { AACancel } }, CancelableAfter = 0.1 }`: skill sem `AACancel` é recusada, com `AACancel` cancela; Stun cancela skill Self/Out e não cancela Locked.

**F2.4 — Sessões de hitbox por dono.** Problema: hit da arma vai pra TODO runner vivo registrado como owner. Q vivo recebe os hits do M1 (dano duplicado); trocar de arma perde os owners. Spec:

- `StartHitbox(duration, owner, opts?)` cria uma SESSÃO ligada ao runner `owner` (dedup de alvos por sessão; várias sessões simultâneas convivem). `hitResult.owner = owner`; só aquele runner recebe `onHit`.
- Sessão termina no fim do tempo, no `StopHitbox(session)` ou quando o runner dono termina.
- `HitboxSpawner` (hitbox de área sem arma) devolve o MESMO formato de `hitResult` (regra 17: um tipo só em `Types`).
- Remove `AddHitboxOwner`/`RemoveHitboxOwner` do `start`/`endSkill` (restrição provisória do F1.5). Quem quer observar hits alheios usa `Listen(OUT.onHit)`, não owner. Só crie `AddHitObserver` se a R5 mostrar consumidor que não cabe no TriggerSet.

**F2.5 — `runner:Damage(target, amount, opts)`.** Spec: `opts = { Hit = hitResult?, Traits = {string}?, Effects = {...}?, Prescaled = boolean? }`. Monta o contexto uma vez e chama `DamagePipeline.Deal` (F2.7). `context.hit = { instance, position, normal, flags }`; os `flags` da Part de hitbox são MESCLADOS (sem duplicar) em `context.traits`, pra listeners filtrarem por `Head`, `Spikes` etc. Nenhuma skill monta contexto de dano na mão depois disso.

**F2.6 — `Combat/Attribution.luau`.** Problema: num DOT, `runner.Entity` é o PORTADOR; `HealthComponent:Die(killer)` credita a morte à vítima. O plano antigo fazia o walker só dentro do DamageScale. Spec (módulo burro, sem estado):

- `GetEffectOwnerRunner(runner)`: sobe `runner.Source` (limite `MAX_ATTRIBUTION_DEPTH = 8`) até o runner de tipo Skill que originou o efeito.
- `GetEffectOwnerEntity(runnerOrContext)`: entidade dona desse runner.
- `GetCausalRoot(lineage)`: `Lineage.Origin` (raiz CAUSAL, não é dona do efeito — reflexo de dano tem raiz no atacante original e dono no refletor).
- `GetOwnerChainRoot(entity)`: sobe `ParentEntity` (F2.10) até a raiz (minion de minion → jogador).
- `BuildContext`/`Deal` preenchem `context.ownerEntity`. `Die` usa o dono: `OUT.OnDeath` é emitido no dono do efeito (D3).

**F2.7 — `Combat/DamagePipeline.luau` (ponto ÚNICO de dano).** Substitui o hook do plano antigo em `Helper.BuildContext` (que é fábrica genérica usada por Heal, Die, `_TriggerShield` e reações com `parentContext`: escalar ali dá dupla escala em repasse membro→corpo e reflexo). Ordem de `Deal(target, context)`:

1. `ValidateHit` (alvo vivo, com Health, não invulnerável).
2. Escala da origem uma vez (`data.damageScale = { From = Source|Holder|None, Live, OnSourceLost = Last|Neutral }`, default Source/Live/Last; lê o stat `DamageMult`), a menos que `Prescaled`. Grava `context.baseDamage`, `context.damageScale`, `context.scaled = true`.
3. `OUT.PreDealDamage` (breakpoint NOVO, no dono do efeito, lado do atacante, com o alvo no contexto). Sem isso, "próximo golpe +40%", crítico e "+X% em alvo abaixo de 30% HP" não têm onde morar: modificador de stat não enxerga o alvo, e `OUT.OnDamage` roda depois do HP mudar.
4. Mitigação existente (block/parry) → `context.blocked` (`Full`/`Partial`/nil).
5. `Defense` (D1), exceto trait `TrueDamage`.
6. `IN.PreDamage` no alvo (pode mutar/zerar).
7. HP. `context.lethal`; dano ≤ 0 NÃO faz early-return: segue com `context.zeroDamage = true` (skill de dano 0 que só aplica slow precisa dos efeitos e eventos).
8. `context.effects`: não aplica se `blocked == Full` sem `ApplyOnBlock` (D2), nem se `lethal`.
9. `IN.PostDamage` no alvo; `OUT.OnDamage` no dono (D3 pra indireto).
10. `Die` se ainda `HP <= 0` DEPOIS do PostDamage (listener de "trapaceia a morte" consegue curar antes).

- `HealthComponent.TakeDamage` vira interno. Call-sites da R5 migram pra `runner:Damage`/`Deal`. Alias antigo com warn de depreciação.
- `Bleed` migra pra `self:Damage(..., { Traits = { DOT } })`. Teste: repasse `Prescaled` não escala duas vezes; hit Full-block não aplica Bleed; Bleed que mata credita o aplicador; `PreDealDamage` vê o alvo; dano 0 aplica efeito.

**F2.8 — `Heal(amount, { Source, Traits })`.** Hoje Heal não tem fonte. Spec: mesmo esqueleto do Deal: `IN.PreHeal` (breakpoint novo: anti-cura) → HP → `OUT.OnHeal` no dono. Lifesteal = `Heal` com `Source = runner` e trait `Lifesteal`.

**F2.9 — API de Status.**

- `GetStatusSnapshot(nameOrID)` → `{ name, ID, stacks, remaining, duration, ownerEntity, traits, persistent }` (cópia, nunca a entrada interna).
- `QueryStatuses(traitQuery)` → lista de snapshots.
- `Enum.EndReasons = { Expired, Cancelled, Cleansed, Transferred, Interrupted, Failed, OwnerEnded, Replaced, OwnerDied }`; o runner guarda `endReason` e o contexto de `onEnd`/`onCancel` recebe.
- `Combat/StatusTransfer.luau`: `Transfer(from, statusID, to, { KeepRemaining = true, KeepStacks = true, NewSource? })` (encerra na origem com `Transferred`), `Steal` = Transfer com `NewSource` = ladrão, `Copy` (não remove). Ignora `persistent` salvo `opts.IncludePersistent`.
- `data.persistent = true`: `ClearAll` pula (a menos de `ClearAll({ IncludePersistent = true })`). Sobreviver a respawn NÃO é papel do motor (o jogo reaplica); documente.
- Traits `Buff`/`Debuff` padronizadas no Enum (confira os valores atuais; regra 19).

**F2.10 — Hierarquia, query, facção, aquisição de alvo.**

- `EntityCore.ParentEntity`, `Children`, `GetRootOwner()`. `DataManager.Create(..., parentEntity)` hoje descarta o pai (só usa pro Fork): passe a gravar. `data.OnParentDestroyed = Destroy | Detach | Keep`.
- `EntityCore.Traits` (traits de ENTIDADE: `Boss`, `Mechanical`, `Structure`, `Limb`...) consultáveis por TraitQuery.
- `DataManager.Query({ Traits?, HasComponents?, Within = { Position, Radius }?, Relation = { To, Is }?, Filter? })` e `ForEach(query, fn)`. Varredura linear por enquanto; custo medido no T3 (RTS).
- `Combat/Relations.luau`: `GetRelation(a, b)` → `Enum.Relations = { Self, Ally, Enemy, Neutral }`. Mesma raiz de dono = Ally; senão matriz da `DataBase/FactionDatabase`; sem facção = Enemy (comportamento atual). Possessão não troca facção.
- `FactionComponent` (`SetFaction`/`GetFaction`), barato.
- Hitbox (arma e spawner) filtra por relação: `opts.Affects = { Enemy = true, Neutral = true }` default.
- `Combat/TargetAcquisition.luau`: `FindBest({ From, Origin, Direction, Range, ConeAngle, RequireLoS, Relation, Query, Sort = Nearest | LowestHP | AngleThenDistance, Exclude })`, `FindAll(...)`, `ValidateTarget(from, target, constraints)`. Substitui `findNearestHealthEntity` da `GrandIntegrationDemo`.

**F2.11 — Herança de reações (D4).** Problema: `TriggerSet:Fork` copia subs com `Owner`, mas `UnsubscribeByOwner` no pai não alcança as cópias; reações adicionadas ao pai depois do spawn não chegam ao filho. Spec (Live): o TriggerSet do filho guarda referência ao do pai; no `Emit`, junta as subs herdáveis dos ancestrais (`Inherit.Generations >= distância`), respeitando TTD e `_removed`. `Limit.Scope`: `Holder` = contagem por entidade, `Branch` = compartilhada pelo ramo, `Tree` = pela árvore. Ordem por Priority + seq existente (determinística). Cache da lista herdada por breakpoint, invalidado por um contador de versão de cada ancestral (custo O(profundidade) pra checar). `Inherit.Mode = "Snapshot"` mantém o Fork, mas as cópias guardam `_origin` e são puladas se `_origin._removed`. Teste: reação adicionada ao pai depois do spawn chega ao filho; remover no pai remove no filho; `Limit Tree Max=1` dispara uma vez na árvore toda; cadeia cíclica termina pelo `MAX_RECURSION`.

**F2.12 — `Modules/Replication/ReplicatedState.luau`.** Hoje o cliente só recebe `SkillFired` no cast: sem loadout, cooldown, cargas, munição, stacks. Spec: `SetPublic(entity, key, value)` → atributo `FW_<key>` no Model (estado apresentável a todos); `SendPrivate(entity, key, value)` → só pro jogador que CONTROLA a entidade (segue a possessão; `Resync(player)` manda o snapshot inteiro na troca de corpo). Chaves em `Enum.ReplicatedKeys`. Envio em lote: chaves sujas acumuladas e 1 `FireClient` por jogador por Heartbeat. Emissores do motor: `LoadoutChanged`, `CooldownChanged { key, endsAt = workspace:GetServerTimeNow() + cd, duration }`, `ChargesChanged`. Componentes novos (ex: AmmoComponent) usam o mesmo módulo.

**F2.13 — Tempo do runner, AttackSpeed, Haste, hitstop, callbacks que yieldam.**

- `Enum.Stats`: `AttackSpeed` (multiplicador, 1 = base) e `CooldownHaste` (D7).
- `runner.timeScale` efetivo = base da skill (`data.timeScale = Enum.TimeScale.AttackSpeed` lê o stat; número = fixo) × multiplicador externo (`runner:SetTimeScale(mult, duration?)`, usado pra hitstop e buffs de cast). O scheduler avança `elapsed += dt * timeScale`; animações tocadas pelo runner acompanham (F2.15). NUNCA mutar `skill.data` (é compartilhado entre instâncias).
- CD final = `cd * 100/(100 + Haste)` × `data.cooldownScale` opcional.
- Callbacks que yieldam hoje quebram o loop do scheduler. Spec: chamar callbacks via `coroutine`; se voltar `suspended`, warn `[FW] callback yieldou: <skill>.<callback>` e seguir o loop (o callback continua sozinho). Documentar: callbacks não devem yieldar.

**F2.14 — Payload no input.** `RequestIntent(intent, isDown, payload?)`, `payload = { TargetID: string?, Point: Vector3? }`. `InputValidator` valida tipos, `Point` finito e dentro de `MAX_POINT_RANGE`, `TargetID` existente. `Intents.NewEvent` carrega o payload; `GestureResolver` repassa; o runner expõe `self.Input.Payload`. O payload é DICA: a skill revalida com `TargetAcquisition.ValidateTarget`. A IA usa o mesmo caminho.

**F2.15 — Helpers "owned" no runner (fim do `self.cleanUp` manual).** Todos construídos em cima do `Own`/`Listen` que já existem, desfeitos no teardown: `ListenOn(entity, role, bp, query, fn)`, `PlayAnimation(anim, opts)` (para no fim salvo `opts.Persist`; velocidade segue `timeScale`), `OnMarker(key, marker, fn)`, `ApplyStatus(target, status, { Owned = true })` (`EndReason.OwnerEnded`), `AddForce(target, data, { Owned = true })`, `StartHitbox`, `StartCooldown`, `SetLoadoutSlot`. Atualize o DOC removendo o padrão `self.cleanUp`.

**F2.16 — Arma e personagem desacoplados.**

- `EquipWeapon(nameOrModel, data?)`: dado da `WeaponDatabase` (F1.16) ou passado; modelo passado ou buscado em `ReplicatedStorage.Assets.Weapons`. Arma no personagem achada por atributo/tag, não por nome de pasta. `WeaponComponent` funciona sem Combat (regra 20); com Combat, publica a camada `WeaponMode`. Hoje o `WeaponModel` é ignorado quando há Combat: corrigir.
- Combat sem personagem default (`"Schema"` hardcoded sai). `config.Char` opcional; `config.Loadout` opcional (NPC de 2 skills não precisa de entrada no CharacterDatabase).
- `formData.Passives = { statusKey... }`: aplicados como `persistent` e owned pela forma ao entrar; removidos com `EndReason.Replaced` ao sair. (Passiva por forma é padrão de kit, não pode ficar a cargo da skill de troca: qualquer outro caminho que troque a forma desincroniza.)
- Skills declaram animações em `data.anims` (fim da busca por pasta).
- `SkillDatabase.Register(key, module)` pra skill criada em runtime (composta/roubada), com erro em colisão de nome/caixa (regra 19).

**F2.17 — Migração e limpeza.**

- `M1`/`Dash`/`Ultimate`/`Skill1-3` pras APIs novas (`runner:Damage`, sessões, política de interrupção, helpers owned). Bug do M1: o marker `End` do 1º golpe executa o `cleanUp` do 2º (some com o `OnMarker` owned). `Ultimate` para de gravar `targetEntity.forceID` na vítima (guarda no runner).
- `WeaponTransform` → `BaseSkills/ModeSwap.luau` genérico (próximo modo declarado ou `data.TargetMode`; `TransformTime`; camada `WeaponMode`). Apaga o do Schema.
- DOC único em `ServerStorage/!DOC/` (apaga a cópia), corrigindo o padrão de utilitário dentro de `callbacks` (usar função local de módulo) e documentando tudo da Fase 2.
- `Enum.Traits`: chave e valor consistentes (hoje `Stackable = "stackable"`, `DOT = "DamageOverTime"`); regra 19.
- `Types.Subscription.Role` diz `"Target" | "Source"`, o resto do código usa `IN`/`OUT`: unificar no Enum.

**F2.18 — Testes da Fase 2.** Um teste por item acima (os marcados em cada item) + regressão da Fase 1. Rodar `GrandIntegrationDemo` sem workarounds.

PARE. Relatório da Fase 2.

### FASE 3 — Aceitação: implementar SEM editar o motor

Regra desta fase: só é permitido criar/editar skills, status, componentes NOVOS, entradas de Enum/Database e módulos utilitários. Se precisar tocar num arquivo do motor, NÃO toque: registre `GAP-xx` e implemente o workaround mais limpo (ou deixe o item pendente). O entregável principal é a lista de GAPs, no formato:

`GAP-xx | cenário | o que faltou | arquivo do motor que teria de mudar | workaround usado | proposta de ponto de expansão`

Locais: `DataBase/SkillDatabase/Tambor/`, `DataBase/SkillDatabase/Arcanista/`, `DataBase/CharacterDatabase/Tambor/`, componentes novos em `EntityData/Components/`, cenários em `Scripts/Tests/Acceptance/`. Números abaixo são placeholders de balanceamento: coloque todos no `data` da skill, nunca no corpo.

**T1 — Kit "Tambor" (duelista lâmina ↔ revólver de 6 câmaras).** Formas: `Lamina` e `Cano` no CharacterDatabase, cada uma com loadout completo na camada `Form` e `Passives` (F2.16). Arma com dois modos só visuais/hitbox (sem loadout; testa que a camada Form basta). `AmmoComponent` (novo): 6 câmaras `Empty | Normal | Heavy` com ponteiro circular; sem reload. `LoadNext(kind, n)` (preenche vazias a partir do ponteiro), `Fire()` → tipo consumido (`Empty` = clique seco), `CountLoaded()`, `EmptyAll()` → `{ normal, heavy }`, `SkipChamber()`. Replica via `ReplicatedState` (privado: câmaras; público: contagem pra VFX). Componente e não Status porque `ClearAll` não pode apagar munição. Cadência (status global, `stackOnSelf`, max 6, 2.5 s, renova no máximo): +8% `AttackSpeed` por stack (modificador owned). Ganha 1 por tiro que ACERTA (listener da passiva do Cano, `All = { Shot }`); tiro que erra remove 2. Persiste na troca de forma: é isso que alimenta o combo na Lâmina. Passivas: Lâmina "Sede de Aço" = `OUT.OnDamage` com `All = { Melee }, None = { DOT }` → `Heal(12%, { Source, Traits = { Lifesteal } })`. Cano = ganho de Cadência. M1 Lâmina: combo de 3 (`ComboWindow`), `timeScale = AttackSpeed`, política `{ InterruptBy = { Any = { AACancel } } }` aberta no marker `Hit`. Cada hit carrega 1 `Normal` (ou `Heavy` se consumiu `Engatilhado`). M1 Cano: dispara a câmara do ponteiro. Normal = base; Heavy = +40% dano e +80% knockback; vazia = clique seco (recuperação curta). Hitscan, traits `Shot`, `Ranged`. Q Lâmina "Tríade": 3 recasts em 3.5 s, `cooldownStart = OnEnd`, trait `AACancel`; o 3º arremessa (Force Hard). Cada hit é melee (carrega câmara, lifesteal). Q Cano "Esvaziar o Tambor": exige ≥1 câmara (senão `runner:Fail`); dispara todas as carregadas em sequência (intervalo escalado por AS) e fecha com "Tiro de Misericórdia" = `base × (1 + 0.15·gastas + 0.35·heavyGastas)`. W Lâmina "Engatilhar": 3 cargas (`data.charges`). Aplica `Engatilhado` em si: no `OUT.PreDealDamage` do próximo golpe `Melee`, +40% e consome; esse golpe carrega `Heavy`. W Cano "Roleta Russa": só lança no Cano; status 8 s que persiste na troca. O servidor sorteia a câmara "viva" (destino, independente da munição). Cada "puxada" avança o destino: no Cano, cada tiro disparado (inclusive os do Esvaziar); na Lâmina, cada hit melee. Puxada segura → `Adrenalina` (+6% `DamageMult`, max 5). Recast Hold/Release com skillcheck `HeldTime ∈ [0.45, 0.60]` = pula uma câmara do destino sem resolver. BANG: no Cano, o próximo tiro sai ×3 com `TrueDamage` e o CD do Q Cano zera; na Lâmina, explosão em área (relação `Enemy` + o próprio Tambor por 10% do HP máx, dano atribuído a ele mesmo; a Sede de Aço NÃO pode curar com esse auto-dano). A Roleta termina no BANG. E Lâmina "Arrancar": golpe que rouba 1 buff do alvo (`QueryStatuses` com `Buff`, maior tempo restante; `StatusTransfer.Steal`) e carrega 1 `Heavy`. E Cano "Girar o Tambor": carrega 2 `Normal` e aplica `Couraça` (+15 `Defense`, 3 s, max 3). Enquanto em CD, cada tiro que acerta reduz o CD do E em 0.5 s (`ReduceCooldown`). Dash Lâmina "Travessia": não-target, Force Hard 0.25 s na direção do input, sessão de hitbox no caminho (1 hit por inimigo pela dedup da sessão), `AACancel`. Atravessar corpos: se não houver API de colisão por entidade, `GAP`. Dash Cano "Encurralar": exige inimigo a ≤22 studs com LoS (`TargetAcquisition`); aceita `Payload.TargetID` revalidado; sem alvo → `Fail` (sem CD). Dash em QUALQUER direção do input; depois dispara `N = max(1, stacks de Cadência)` tiros no alvo, cada um consumindo câmara; sem câmara, o tiro sai com 40%. R "Troca de Guarda" (slot Ultimate): `ModeSwap` + `SetCharMode`, CD 3 s. Aplica `Transição` (1.2 s): a 1ª skill lançada durante ela roda com `timeScale ×2` (listener de `OUT.onStart` chama `ctx.runner:SetTimeScale(2)`). Roteiro de aceitação (`Scripts/Tests/Acceptance/Tambor.server.luau`, logs com `[FW-DEBUG]`):

1. Cano: 6 tiros no dummy → Cadência 6, AS +48%, câmaras vazias; tiro em vazio não mexe em stacks; tiro errado remove 2.
2. R → Lâmina: AS continua, cada hit carrega 1 Normal, lifesteal 12% no log; Transição acelera a 1ª skill.
3. Loop: W → M1 cancelado pelo Q antes do fim da animação → 3 recasts na janela; medir o ciclo (alvo ~1 s com 6 stacks); golpe engatilhado dá +40% e carrega Heavy; CD do Q começa no fim; Travessia cancela a animação e sai.
4. R → Cano com câmaras mistas: Esvaziar dispara só as carregadas; Misericórdia confere com a fórmula.
5. Roleta: puxar trocando de forma no meio; BANG em cada forma em execuções separadas; auto-dano atribuído ao Tambor, sem lifesteal; skillcheck certo e errado.
6. Arrancar num alvo com 2 buffs (1 `persistent`): rouba só o não persistente, com tempo restante; o alvo registra `EndReason.Transferred`.
7. Encurralar: sem alvo → falha sem CD; `TargetID` forjado fora do alcance → recusado; 4 stacks → 4 tiros; sem câmaras → 40%; Stun durante os tiros interrompe.
8. Regra 8: um NPC controlado pela IA com o mesmo kit (via intents) e um jogador possuindo esse NPC; a replicação privada segue quem controla.

**T2 — "Arcanista" (skill composta base + elemento).** `BaseSkills/Composer.luau`:

- `Compose(baseKey, elementKeys)` → chave canônica (elementos ordenados), memoizada; nome estável `Composed:<base>+<el1>[+<el2>]` registrado via `SkillDatabase.Register`.
- NUNCA muta módulos fonte. Cada parte enxerga uma view: `setmetatable({ data = elem.data }, { __index = proxy })`.
- Traits = união; `cooldownGroup = "Arcanista:Cast"` (sem isso, trocar de combo contorna o CD).
- Contrato (documentado no cabeçalho, regra 17): a Base declara os pontos de emissão (`onHit`, `onStep`, `onEnd`); o Elemento implementa `Modify(dataView)`, `OnHit(runner, ctx)`, `OnStep(runner, dt)`, `OnEnd(runner)`. Base roda primeiro, elementos na ordem canônica. Bases: `Projetil`, `Area`, `Onda`, `Invocacao`. Elementos: `Fogo` (Burn DOT), `Gelo` (Slow; 3 stacks → `Congelado` com `interrupts`), `Raio` (encadeia em 2 via `TargetAcquisition`, excluindo já atingidos), `Vacuo` (puxão Soft com `Key`). Loadout: Ability1 cicla a base, Ability2 cicla o elemento (camada `Temporary`/`Manual`), Ability3 lança; Ultimate "Fusão" = base + 2 elementos. Teste: as 16 combinações base+1 compõem uma vez só (memo); `Invocacao+Raio` cria minion cujo hit encadeia; `Onda+Vacuo` não empilha força; `Area+Gelo` congela e interrompe o cast do alvo.

**T3 — Cenários de estresse (um script por cenário em `Scripts/Tests/Acceptance/`).**

- Arma modular (roguelike): peças com raridade = modificadores de stat owned pela peça + traits + subs de TriggerSet com `Owner = peça` (desencaixar = `UnsubscribeByOwner` + remover modificadores). Peça "Espinhos": golpe melee com trait `Spikes` dispara os on-hits do jogador e spawna um minion (`ParentEntity` = jogador, herança Live) que herda 2 elementos do jogador (`QueryStatuses` com trait `Element`) e usa uma skill `Composer` que herda `onStep`/`onEnd`; no fim, ela spawna 3 sub-minions que roubam 1 buff por hit. Verificar: kill de sub-minion creditada ao jogador (`GetOwnerChainRoot`, `OUT.OnDeath` no jogador); a cadeia Espinhos → minion → hit → Espinhos TERMINA (`Limit` + `MAX_RECURSION`), sem explosão exponencial.
- Boss 8 braços + 2 pernas: cada membro é entidade filha (`Limb`), com Health e loadout próprio, comandada pelo Brain do boss via `HandleIntent(limb.ID, ...)`. `IN.PostDamage` do membro repassa 50% ao corpo com `Deal(..., { Prescaled = true, Traits = { Repassed } })`. Perna morta → `Mancando` (Slow + força lateral Soft com `Key`). Membro morto não mata o boss; boss morto destrói os membros (`OnParentDestroyed = Destroy`).
- Cartas (Isaac): status `persistent` com trait `Card`, interações via TriggerSet; `ClearAll` não remove; `Steal` não rouba.
- Vento global: script de serviço com `DataManager.ForEach({ HasComponents = { Movement } })` aplicando Soft com `Key = "GlobalWind"` a cada tick; entidades com trait `Anchored` fora via `None`. Jogador ainda anda contra o vento (D6).
- Boss possui minion: `minion.Possess({ AI = true, By = boss })`; Brain do minion suspenso; boss emite intents; `Release` no stagger do boss.
- RTS (Stick War): 60 workers + 40 soldados. Medir e reportar: tempo de criação por entidade, nº de closures de API por entidade, custo por Heartbeat de `MovementController` + `SkillScheduler` + `AIScheduler`. Jogador possui um worker e luta; `Resync` na troca. Se o custo de closures pesar, `GAP` com a proposta de dispatch por metatable compartilhada por classe de componente (não implementar).
- FPS tático: skill hitscan com `runner:Damage` e `context.hit.instance`; Part com `Flags = "Head"` → trait `Head` → multiplicador no `IN.PreDamage`. Lag compensation (rewind no servidor) só como `GAP`.

PARE. Relatório final: GAPs, medições, e o que o dev precisa ver no Studio.

### Apêndice — mapa de paths

- Runner/handler/scheduler: `sync/ServerScriptService/Modules/{SkillRunner,SkillHandler,SkillScheduler,SkillFactory,GlobalAntiCheat,InputSessions}.luau`
- Física: `sync/ServerScriptService/Modules/Physics/{MovementController,Settings,ForceRig}.luau`
- IA: `sync/ServerScriptService/Modules/AI/AIScheduler.luau`
- Entidades: `sync/ServerScriptService/EntityData/{EntityCore,DataManager,ComponentUtils,ComponentsExport,EntityWrapper}.luau`
- Componentes: `sync/ServerScriptService/EntityData/Components/{AI,Animation,Attributes,Character,Combat,Control,Health,Movement,Status,Weapon}Component.luau`
- Scripts/testes: `sync/ServerScriptService/Scripts/{InputValidator,Main}.server.luau`, `.../Scripts/Tests/{GrandIntegrationDemo.server,IntegrationTests.server,TestHarness,VentiladorDemo.server}.luau`
- Combate: `sync/ServerStorage/Modules/Combat/{StateTable,TriggerSet,TraitQuery,Lineage,Types,AreaEffect,AreaBehaviors}.luau`, `.../StateTable/{Enum,Helper}.luau`, `.../ActionStates/{Self,Out,LockedCast}.luau`, `.../Status/Debuffs/Bleed.luau`
- Hitbox: `sync/ServerStorage/Modules/Combat/Hitbox/{HitboxWrapper,HitboxSpawner,HitboxBehaviors}.luau`
- Minions: `sync/ServerStorage/Modules/MinionFactory.luau`
- Databases: `sync/ServerStorage/DataBase/SkillDatabase.luau`, `.../SkillDatabase/BaseSkills.luau` (+`ComboWindow.luau`), `.../SkillDatabase/Schema/*.luau`, `.../CharacterDatabase/Schema/Base.luau`
- Arma (hoje): `sync/ReplicatedStorage/Assets/Weapons/Schema/martelo/WeaponData.luau`
- Input: `sync/ReplicatedStorage/Input/{Intents,GestureResolver}.luau`, `sync/ReplicatedStorage/Config/InputConfig.luau`
- DOC: `sync/ServerStorage/!DOC/*.luau` (duplicata em `sync/ServerStorage/Modules/CharData/!Doc/DOC.luau`)
- Novos desta tarefa: `Combat/{Attribution,DamagePipeline,StatusTransfer,Relations,TargetAcquisition}.luau`, `Modules/Replication/ReplicatedState.luau`, `DataBase/{WeaponDatabase,FactionDatabase}`, `Components/FactionComponent.luau`, `BaseSkills/{ModeSwap,Composer}.luau`

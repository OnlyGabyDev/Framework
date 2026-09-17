---
trigger: always_on
glob:
description: Bugs confirmados e objetivos pendentes
---

_Parte 3 de 4 do contexto do projeto — ver 00 e 01 para regras e arquitetura antes de delegar qualquer bug abaixo._

## Bugs Confirmados e Ordem de Prioridade

(adicione esses arquivos de contexto ao git ignore, não quero dar commit nisso no repo.)

Ordenado por severidade real (bloqueio de runtime + quão fundamental é o
conserto para os objetivos pendentes). **Ao delegar qualquer um destes a um
sub-agente, inclua a descrição completa do bug abaixo, não só o nome.**

1. **`AttributesComponent` ausente em `Main.server.luau`** (regra 16). Não está
   na lista `PlayerComponents`, mas `CombatComponent`, `WeaponComponent` e
   `MovementController` dependem de `GetStat`/`SetStat`/`GetStats`. Causa
   provável do Objetivo 4 (bug de tipo de arma/stats no char DB).
   **Adicional**: mesmo depois de reincluído, `AttributeComponents:OnAdded` tem
   um crash latente — `GetStats()` retorna `{Speed=16, JumpForce=20}` (shape
   achatado) quando a entidade não tem `CombatComponent`, mas o código sempre
   assume `charData["Stats"][Enum.Stats.Speed]` (shape aninhado) sem checar qual
   dos dois veio. Resultado: `attempt to index nil` pra qualquer entidade sem
   Combat (viola regra 5 — entidade simples deveria funcionar sem overhead, não
   crashar). É a regra 17 violada dentro da mesma função: dois shapes de "stats"
   coexistindo, um quebrando o outro.

2. **Reescrita do `SkillRunner`/`Skill` (classe isolada) + remoção de
   `copySkill`** + implementação do sistema de Context por Breakpoint. Ver seção
   "Design Decidido" acima — já fechado, falta implementar.

3. **`CombatComponent:CanContinue` com gate de estado quebrado**: usa
   `#rawState` sobre `GetActiveStates()`, que retorna dicionário chaveado por
   nome (não array) — `#` sobre hash table sempre retorna 0. Resultado: o check
   de `tags["canCast"] == false` nunca é alcançado; Silence/Stun não bloqueiam
   cast pelo caminho principal. Além disso, entidade sem `StatusComponent` e sem
   `PlayerState` ativo retorna `false` sempre — bloqueando cast de entidades
   simples (viola regra 5).

4. **`CombatComponent:TrySelfCancel` com `return` fora do escopo do `if`**:
   dentro do loop `for _, v in pairs(playerStates.Self)`, o `return false` está
   fora do `if self.PlayerState.name == v.data.name`, então a decisão é tomada
   já na primeira iteração, independente do resultado real — comportamento
   depende da ordem de iteração de `pairs` (não determinística).

5. **Blockcast não persiste `_LastCFrameBlockCast`**: em
   `Solvers/Blockcast.module.luau`, `lastCFrame` é local à função `Cast`; o
   `task.defer` que a atualiza nunca escreve de volta em
   `segment.CastData._LastCFrameBlockCast`. Resultado: Blockcast nunca faz sweep
   real, sempre castando da posição atual — risco de tunneling em alta
   velocidade. **Resolver antes do Objetivo 3 (movimentação/dash)**, já que
   dashes mais rápidos vão tornar esse bug visível.

6. **`StatusComponent:RemoveStatusByID` com branch morto**: compara
   `groupName == StateTable.Enum.Status`, mas esse enum não existe
   (`groupName` só pode ser as chaves literais `"status"`/`"state"` de
   `self.Effects`). Toda a lógica de remoção de status empilháveis por ID é
   código morto — só remoção de `state` funciona.

7. **Violações da regra 20** espalhadas — checagem condicional de outro
   componente sem dependência declarada:
   - `WeaponComponent:EquipWeapon` decide comportamento baseado em
     `HasComponent(Combat)`.
   - `MovementController:ProcessEntity` checa `HasComponent(Status)` pra buscar
     tags de movimento.
   - `HealthComponent:TakeDamage` e `CombatComponent:CanContinue` checam
     `HasComponent(Status)` internamente.
   Precisa de levantamento caso a caso: eliminar a dependência ou declará-la
   formalmente (regra 16) quando for estruturalmente inevitável (ex: Health
   validar imunidade plausivelmente é inevitável; Weapon decidir criar hitbox
   com base em Combat provavelmente não é).

8. **Duplicação de nomes** (regra 19): `BaseSkills.module.luau` idêntico em dois
   caminhos (`DataBase/SkillDatabase/BaseSkills` e `Modules/BaseSkills/
   BaseSkills`); pasta de arma duplicada `martelo` (minúsculo, incompleta) vs
   `Martelo` (maiúsculo, completa) em `ReplicatedStorage/Assets/Weapons/Schema`.

9. **Debug output sem padronização** (regra 18): `print()` cru em
   `HealthComponent:TakeDamage`, `CombatComponent:AddSkill`/`_ApplyLoadout`,
   misturado com warns estruturais.

---

## Objetivos Pendentes

Não iniciar antes dos bugs 1–4 acima estarem resolvidos — dependem de fundação
estável (stats corretos, gates de cast funcionando, skill isolada).

1. **Pub/sub interno — checagem pré-output**: antes de uma skill disparar um
   breakpoint pro mundo externo (dano aplicado, debuff propagado), rodar
   checagem por string/tipo de dano/tags, com possibilidade de injeção no ponto
   requisitado. Implementar sobre o `Context` por Breakpoint já desenhado (ver
   Design Decidido) — não como sistema paralelo.

2. **Contagem/estado interno para efeitos aplicados externamente**: caso de uso
   confirmado — debuff que faz os próximos 3 ticks de veneno darem triplo de
   dano, exigindo contador de estado que sobrevive entre ticks.
   **O mecanismo atual do `HealthComponent` (`OnDamage`/`OnHeal`/`OnDeath`/
   `OnRevive`) está quebrado e deve ser substituído, não corrigido**: `_Trigger`
   é definido recebendo um parâmetro (`breakPoint`), mas é chamado como
   `self:_Trigger(self, StateTable.reactTags.onDamage)` — o `:` já injeta
   `self`, então o segundo argumento (`self` de novo) ocupa `breakPoint`, e a
   string do evento real é descartada. Isso roda no construtor, antes de
   `EventListeners` existir, então sempre bate no early-return e retorna `nil`
   — `self.OnDamage` etc. ficam permanentemente `nil`. Mesmo corrigindo a
   assinatura, `_Trigger` tem `return` dentro do `for`, saindo na primeira
   iteração — só o primeiro listener registrado via `Subscribe` seria chamado.
   Construir o novo mecanismo sobre o `Context` por Breakpoint (Objetivo 1)
   elimina a necessidade de reaproveitar esse código.

3. **Reescrita do sistema de movimentação**: atualmente jittery, não suporta
   dash que zera gravidade no ar (movimento linear livre), nem dashes
   complexos com input de câmera durante o dash (ex: ult do Sion). **Depende do
   bug 5 (Blockcast sweep) resolvido antes**, para não mascarar tunneling com
   dashes mais rápidos.

4. **Bug de tipo de arma / char DB**: suspeita forte de que a causa raiz é o
   bug 1 (AttributesComponent ausente + crash de shape) combinado com leitura
   inconsistente de shape de stats entre `AttributeComponents:OnAdded`
   (`charData["Stats"][Enum.Stats.Speed]`) e `CombatComponent:SetChosenChar`
   (`stats.speed`, shape diferente) — violação direta da regra 17. Resolver
   como parte do bug 1, unificando a leitura de stats num único shape
   declarado.

---
trigger: always_on
glob:
description: Instruções de delegação para sub-agentes
---

_Parte 4 de 4 do contexto do projeto — instruções de como delegar as tasks descritas em 02-bugs-e-objetivos.md._

## Instruções de Delegação para Sub-Agentes

Ao criar uma task para um sub-agente de implementação:

1. Cite a(s) regra(s) numerada(s) relevante(s) do framework, não parafraseie.
2. Se a task tocar em dado compartilhado (Context, CastData, StatusData,
   CharacterDatabase shape), cole o shape declarado nesta seção, não deixe o
   sub-agente inferir.
3. Escopo fechado: arquivo(s) exato(s), função(ões) exata(s), comportamento
   esperado antes/depois.
4. Sub-agente não deve introduzir novo padrão de acesso a dado compartilhado
   sem reportar de volta para você validar contra a regra 17.
5. Sub-agente não deve adicionar `HasComponent` condicional novo sem declarar
   a dependência (regra 16) ou justificar por que é estruturalmente inevitável
   (regra 20).
6. Qualquer print/warn de debug introduzido deve seguir o padrão definido na
   regra 18 (prefixo consistente — a definir o prefixo exato antes do primeiro
   uso, ex: `[DEBUG]`).
7. Reporte de volta qualquer nome de arquivo/pasta duplicado ou
   case-diferente encontrado durante a task (regra 19), mesmo que fora do
   escopo da task.
8. Para pesquisas externas simples (confirmar API do Roblox, verificar se uma
   solução mais recente existe), delegue a busca em vez de gastar raciocínio do
   orquestrador nisso — reserve profundidade de análise para decisões que
   afetam múltiplos módulos ou regras do framework.

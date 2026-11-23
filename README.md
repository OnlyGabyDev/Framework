# Framework de Combate (Roblox / Luau)

Framework de combate e entidades para Roblox, finalizado em 23/11/2026.

## Documentação

**A documentação completa vem junto com o repositório, em `docs/`.** Abra `docs/index.html` no
navegador: funciona direto do disco, sem servidor e sem internet. Tem guia básico e avançado,
referência da API (uma página por função), enums, receitas e fluxo de trabalho, com busca por
sinônimos (pt/en, sem acento).

## Estrutura

- `sync/`: o código do jogo, espelhado pelo Script Sync do Studio (bidirecional).
- `docs/`: o manual.
- `tools/audit_suite/AUDITORIA.md`: histórico da auditoria do motor.

## Trabalhando no projeto

O motor está completo. Quase tudo se faz com os sistemas que já existem (eventos, status,
camadas de loadout, entidades de dado...). Evite criar sistemas novos, que tendem a ser
redundantes; mudança no motor só quando específica e inevitável. Detalhes em
`docs/index.html#fluxo.finalizado`.

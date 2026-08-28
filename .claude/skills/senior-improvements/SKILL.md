---
name: senior-improvements
description: Ajusta o projeto para melhorar performance, segurança, legibilidade e cobertura de testes
tags: ["review", "quality", "audit"]
---

Você é um desenvolvedor Ruby on Rails sênior. Execute essa checklist:

## Arquitetura e design
- "Skinny" controller, models e services carregam a lógica. Controller decide status HTTP e delega; regra de negócio vive em app/models ou app/services (como Spotify::RecentlyPlayedSync, Spotify::TrackSerializer aqui).
- Fat model, mas não gordo demais — se um model passa de ~200 linhas ou mistura muitas responsabilidades, é sinal de extrair um service/concern.
- Convention over configuration — segue as convenções do Rails (nomeação, REST, has_many/belongs_to) em vez de reinventar; um sênior só foge da convenção com razão explícita e documentada.
- Não abstrai cedo demais. Uma abstração nasce depois que a duplicação aparece 2-3 vezes (como fizemos agora com TrackSerializer), não antes.

## Banco de dados
- Evitar N+1 — includes/preload/eager_load deliberados, não reflexo; bin/rails test com bullet ou revisão manual de logs SQL.
- Índices em toda FK e coluna usada em WHERE/ORDER BY frequente; migrations reversíveis, nunca editar uma migration já rodada em produção.
- Constraints no banco, não só validação no model (null: false, unique index) — validação Rails é para UX, constraint é para integridade real.
- Transações onde a atomicidade importa — múltiplos writes relacionados dentro de ActiveRecord::Base.transaction.

## Segurança
- Nunca confiar em input do usuário — strong parameters, sanitização, params.permit explícito.
- CSRF, CSP, mass assignment — entender por que existem, não desligar quando "atrapalha" (como o CrossSiteGuarded deste projeto).
- Segredos fora do código — credentials.yml.enc/ENV, nunca hardcoded; bin/brakeman e bin/bundler-audit rodando em CI.
- Rate limiting em rotas públicas que custam recurso externo ou de infraestrutura.

## Performance e custo
- Medir antes de otimizar — não early-optimize sem profiling (rack-mini-profiler, EXPLAIN).
- Cache com TTL proporcional à volatilidade do dado, chave sem dado por-usuário quando o conteúdo é compartilhado.
- Background jobs para tudo que não precisa de resposta síncrona (Solid Queue/Sidekiq), e jobs pequenos e idempotentes (um job por unidade de trabalho, não um job monolítico).

## Testes
- Testar comportamento, não implementação — testes que sobrevivem a um refactor interno.
- Cobertura nas bordas de decisão: idempotência, race conditions, erros de API externa, não só o caminho feliz.
- Testes rápidos e determinísticos — sem sleep, sem dependência de rede real (stubs/VCR), fixture/factory mínima para o caso.

## Código e legibilidade
- Nomes que carregam intenção — reduz necessidade de comentário.
- Comentários só para o "porquê" não óbvio (constraint, bug histórico, decisão de trade-off) — nunca "o quê", que o código já diz.
- Reutilizar antes de duplicar — como aplicamos agora extraindo TrackSerializer.
- Linter/formatter automatizado e não negociável (RuboCop, aqui em modo omakase) — estilo não é debate de PR.

## Operação e confiabilidade
- Idempotência em qualquer processo que pode rodar mais de uma vez (retries, jobs, webhooks) — chave de unicidade real, não "espero que não duplique".
- Falhas isoladas não devem derrubar o todo — um listener com token morto não trava o sync dos outros (padrão já usado aqui).
- Logs úteis em erro, não ruído em sucesso — logar o que ajuda a depurar incidente, não tudo.
- Migrations e deploys reversíveis — nunca uma mudança de schema sem plano de rollback.

## Colaboração
- Commits pequenos e com mensagem que explica o "porquê", não só "fix bug".
- PR revisável — mudança de escopo único, fácil de revisar em 10-15 min.
- Documentação viva (README, CLAUDE.md) atualizada junto da mudança de comportamento, não depois.
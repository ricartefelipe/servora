# Status

Atualizado a cada pull request. Itens só aparecem como concluídos quando há implementação e teste.

## Concluído

| Área | Entrega | Evidência |
|---|---|---|
| Fundação | Rails 8.1, PostgreSQL 18, papéis owner/aplicação, privilégios reaplicáveis | `spec/database/roles_spec.rb`, `spec/lib/servora/database_privileges_spec.rb` |
| Operação | Liveness `/up` e readiness `/ready` | `spec/requests/health_spec.rb` |
| Infraestrutura | Dockerfile multi-stage, Compose (db, mailpit, migrate, web, worker, css), CI | `.github/workflows/ci.yml` |

## Verificações executadas localmente

| Verificação | Resultado |
|---|---|
| `bundle exec rspec` | 12 exemplos, 0 falhas |
| `bundle exec rubocop` | sem ofensas |
| `bundle exec bundler-audit check --update` | sem vulnerabilidades |

## Em andamento

- Identidade, organizações, membros, convites, papéis e RLS aplicada às tabelas de tenant.

## Ponto de continuidade

Próxima branch: `feature/identidade-e-organizacoes` a partir de `develop`.

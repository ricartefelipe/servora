# Status

Atualizado a cada pull request. Itens só aparecem como concluídos quando há implementação e teste.

## Concluído

| Área | Entrega | Evidência |
|---|---|---|
| Fundação | Rails 8.1, PostgreSQL 18, papéis owner/aplicação, privilégios reaplicáveis | `spec/database/roles_spec.rb`, `spec/lib/servora/database_privileges_spec.rb` |
| Operação | Liveness `/up` e readiness `/ready` | `spec/requests/health_spec.rb` |
| Infraestrutura | Dockerfile multi-stage, Compose (db, mailpit, migrate, web, worker, css), CI | `.github/workflows/ci.yml` |
| Multitenancy | Contexto transacional, RLS, FKs compostas, histórico append-only, função `SECURITY DEFINER` | `spec/lib/servora/tenancy_spec.rb`, `spec/database/tenant_isolation_spec.rb` |
| Identidade | Cadastro, confirmação por POST, login, bloqueio, recuperação, sessões revogáveis, MFA TOTP | `spec/requests/authentication_spec.rb` |
| Organizações | Onboarding, seleção e troca validadas, configurações | `spec/requests/onboarding_spec.rb`, `spec/requests/tenancy_spec.rb` |
| Equipe | Papéis, matriz de permissões, convites de uso único, desativação imediata, último proprietário protegido | `spec/requests/team_spec.rb`, `spec/services/**`, `spec/policies/**` |
| Auditoria | Registro imutável com redação e consulta filtrada | `spec/models/identity_spec.rb`, `spec/requests/team_spec.rb` |
| Interface | Layouts, navegação por permissão, estados de erro/acesso negado, menu acessível no mobile | `spec/system/**` |

## Verificações executadas localmente

| Verificação | Resultado |
|---|---|
| `ruby bin/test-all` | 21 exemplos (regras puras) + 105 exemplos (Rails e system) — 0 falhas |
| Cobertura do núcleo | linhas 98,70%, branches 86,96% |
| `bundle exec rubocop` | sem ofensas |
| `bundle exec brakeman --exit-on-warn` | sem avisos |

## Em andamento

- Transactional Outbox e notificações.

## Ponto de continuidade

Próxima branch: `feature/outbox-e-notificacoes` a partir de `develop`. O envio de convites usa
`perform_later` após o commit e será migrado para eventos da outbox nessa feature.

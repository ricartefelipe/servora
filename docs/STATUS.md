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
| Outbox | Publicação transacional, claim com lease e SKIP LOCKED, retentativas, falhas definitivas, reprocessamento auditado | `spec/services/outbox/**` |
| Notificações | Notificações internas idempotentes, stream privado por vínculo com autorização no canal | `spec/channels/**`, `spec/requests/outbox_and_notifications_spec.rb` |
| Clientes | PF/PJ com CPF/CNPJ, locais, contatos (aprovação, acompanhamento, portal), busca, arquivamento, bloqueio otimista | `spec/requests/customers_spec.rb`, `spec/services/customers/**` |
| Equipamentos | Cadastro, local do mesmo cliente garantido no banco, mudança de local, transferência, estado operacional, histórico, arquivamento | `spec/services/equipment_lifecycle/**`, `spec/database/customer_integrity_spec.rb` |
| Responsividade | Sem rolagem horizontal nas telas principais em 390 px | `spec/system/responsive_spec.rb` |
| Catálogo | Serviços e peças, preço de venda, custo restrito, busca | `spec/requests/quotes_spec.rb`, `spec/queries/catalog_search_query_spec.rb` |
| Orçamentos | Numeração atômica, versões, snapshot e digest, triggers de imutabilidade, descontos, validade, cancelamento, histórico | `spec/services/quotes_spec.rb`, `spec/services/numbering_spec.rb` |
| Aprovação | Decisão pelo portal ou registro interno com evidências; recusa de versão substituída, expirada, digest divergente e contato não autorizado | `spec/services/quotes_spec.rb`, `spec/system/quote_approval_flow_spec.rb` |
| Portal do cliente | Link de uso único (GET não consome), sessão restrita revogável, isolamento por cliente | `spec/requests/portal_spec.rb`, `spec/services/portal/**` |
| Ordens de serviço | Abertura, conversão idempotente (inclusive concorrente), máquina de estados, checklist obrigatório, registro técnico com bloqueio otimista, itens adicionais com autorização, conclusão com relatório versionado, cancelamento e reabertura | `spec/services/work_orders_spec.rb`, `spec/services/work_orders/create_from_quote_spec.rb`, `spec/system/work_order_flow_spec.rb` |
| Técnicos | Escopo restrito a ordens e equipamentos atribuídos, sem preços e sem conclusão formal | `spec/policies/work_order_policy_spec.rb` |
| Agenda | Visão diária (linha do tempo) e semanal, técnicos e equipes, horários, ausências, deslocamento, competências | `spec/requests/scheduling_spec.rb`, `spec/system/scheduling_flow_spec.rb` |
| Despacho | Reserva protegida por exclusion constraint, equipe atômica, reagendamento seguro, cancelamento e ausência do cliente, sugestão determinística | `spec/services/scheduling/**`, `spec/services/visits_spec.rb` |
| Apontamentos | Minutos e custo de mão de obra com custo/hora vigente; idempotência por operação | `spec/services/time_entries/record_spec.rb` |

## Verificações executadas localmente

| Verificação | Resultado |
|---|---|
| `ruby bin/test-all` | 53 exemplos (regras puras) + 267 exemplos (Rails e system) — 0 falhas |
| Cobertura do núcleo | linhas 99,11%, branches 84,79% |
| `ruby bin/db-structure --check` | migrations, rollback e recarga consistentes |
| `bundle exec rubocop` | sem ofensas |
| `bundle exec brakeman --exit-on-warn` | sem avisos |

## Em andamento

- Release 0.1.0 (primeira fatia vertical), seguida do módulo de estoque.

## Ponto de continuidade

Após o merge desta feature: `release/0.1.0` a partir de `develop` → PR para `main` → tag `v0.1.0` →
PR de reintegração para `develop`. Em seguida, `feature/estoque`.

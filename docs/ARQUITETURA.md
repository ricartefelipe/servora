# Arquitetura

## Visão geral

Monólito modular Rails. Cada contexto de negócio tem seus models, casos de uso, consultas, policies,
controllers e views agrupados por namespace. O PostgreSQL é a fonte de verdade das invariantes críticas.

### Camadas

| Camada | Diretório | Responsabilidade |
|---|---|---|
| Regras puras | `app/domain` | Cálculos e políticas sem I/O (dinheiro, recorrência, SLA, custo médio, máquinas de estados). Testadas sem Rails. |
| Models | `app/models` | Associações, validações e comportamento próprio das entidades. |
| Casos de uso | `app/services` | Operações que coordenam várias entidades em transações explícitas. |
| Consultas | `app/queries` | Consultas compostas e relatórios. |
| Formulários | `app/forms` | Operações compostas apresentadas como um formulário. |
| Autorização | `app/policies` | Pundit: permissões por papel e escopos. |
| Integrações | `app/integrations` | Adaptadores de serviços externos (pagamentos, webhooks). |
| Jobs | `app/jobs` | Processamento assíncrono; recebem apenas identificadores. |
| Infraestrutura | `lib/servora` | Tenancy, privilégios de banco, logs, métricas, cliente HTTP. |

Controllers apenas coordenam HTTP, autorização e chamada do caso de uso.

## Estratégia de multitenancy

Defesa em profundidade, em cinco camadas independentes:

1. **Escopo explícito**: consultas partem de `current_organization` ou de `policy_scope`.
2. **Pundit**: toda ação passa por `authorize`; escopos filtram por papel (técnico vê apenas o que lhe foi atribuído).
3. **Chaves compostas**: tabelas de tenant expõem `UNIQUE (organization_id, id)` e as referências usam
   `FOREIGN KEY (organization_id, x_id) REFERENCES x (organization_id, id)`. Referência entre organizações
   é impossível no banco.
4. **Row-Level Security**: policy `tenant_isolation` em toda tabela de tenant, baseada em
   `servora_current_organization_id()`.
5. **Papel sem bypass**: a aplicação conecta como `servora_app` (sem superuser, sem BYPASSRLS, sem posse de tabelas).

O contexto é definido por `set_config(..., true)` (local à transação) e envolve a ação inteira,
incluindo a renderização. Ausência de contexto resulta em zero linhas. Detalhes em `DECISOES.md` (DEC-003 a DEC-005).

## Processos

| Processo | Comando | Observações |
|---|---|---|
| Web | `bin/rails server` | Puma; nunca executa migrations. |
| Worker | `bin/jobs` | Solid Queue (fila em banco próprio). |
| Release | `bin/db-prepare` | Executado uma vez por deploy com o papel owner. |

## Bancos

| Banco | Conteúdo | Schema |
|---|---|---|
| `servora_<env>` | Dados de negócio (RLS) | `db/structure.sql` |
| `servora_<env>_queue` | Solid Queue | `db/queue_schema.rb` |
| `servora_<env>_cache` | Solid Cache (rate limiting) | `db/cache_schema.rb` |
| `servora_<env>_cable` | Solid Cable | `db/cable_schema.rb` |

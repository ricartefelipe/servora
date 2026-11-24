# Modelo de dados

Todas as tabelas de tenant têm `organization_id`, chave `(organization_id, id)`, RLS e chaves estrangeiras
compostas (referências nunca atravessam organizações). Chaves primárias UUIDv7. Valores monetários em
`numeric(14,2)`, quantidades `numeric(14,3)`, custos unitários `numeric(14,4)`. Instantes em `timestamptz`.

## Núcleo operacional

```mermaid
erDiagram
  organizations ||--o{ memberships : "equipe"
  users ||--o{ memberships : "vínculos"
  organizations ||--o{ customers : ""
  customers ||--o{ service_locations : ""
  customers ||--o{ customer_contacts : ""
  service_locations ||--o{ equipment : "instalado em"
  customers ||--o{ quotes : ""
  quotes ||--o{ quote_versions : "versões (snapshot imutável)"
  quote_versions ||--o{ quote_items : ""
  quote_versions ||--o| work_orders : "conversão idempotente"
  customers ||--o{ work_orders : ""
  work_orders ||--o{ work_order_items : ""
  work_orders ||--o{ work_order_checklist_items : ""
  work_orders ||--o{ work_order_transitions : "histórico"
  work_orders ||--o{ work_order_reports : "versões do relatório"
  work_orders ||--o{ visits : ""
  visits ||--o{ technician_allocations : "EXCLUDE sobre tstzrange"
  memberships ||--o{ technician_allocations : ""
  work_orders ||--o{ time_entries : ""
  work_orders ||--o{ work_order_evidences : "anexos"
  contracts ||--o{ work_orders : "cobertura"
  contracts ||--o{ maintenance_plans : ""
  maintenance_plans ||--o{ maintenance_occurrences : "(plano, sequência) única"
  maintenance_occurrences ||--|| work_orders : ""
  work_orders ||--o{ sla_clocks : "primeira resposta e resolução"
```

## Estoque e financeiro

```mermaid
erDiagram
  warehouses ||--o{ stock_balances : ""
  catalog_items ||--o{ stock_balances : ""
  stock_balances ||--o{ stock_movements : "saldo só muda com movimento (trigger)"
  work_orders ||--o{ stock_reservations : ""
  work_orders ||--o{ material_consumptions : "custo histórico"
  work_orders ||--o{ receivables : "parcelas"
  receivables ||--o{ payments : ""
  receivables ||--o{ payment_charges : "uma em andamento"
  receivables ||--o{ financial_events : "append-only"
  work_orders ||--o{ expenses : ""
```

## Integrações, plataforma e infraestrutura

| Tabela | Função |
|---|---|
| `outbox_events`, `outbox_event_failures` | Transactional Outbox com lease, retentativas e falhas |
| `notifications` | Notificações internas idempotentes |
| `audit_events` | Auditoria append-only com redação |
| `api_credentials`, `api_idempotency_keys` | Credenciais da API (digest) e respostas idempotentes |
| `webhook_endpoints`, `webhook_deliveries` | Webhooks de saída (segredo criptografado, entrega única por evento) |
| `inbound_webhooks` | Notificações recebidas, deduplicadas pelo id do provedor |
| `field_operations` | Resultado das operações do aplicativo de campo por id |
| `plans`, `plan_modules` | Catálogo da plataforma (somente leitura para a aplicação) |
| `subscriptions` | Assinatura da plataforma por organização |
| `active_storage_*` | Arquivos com `organization_id` atribuído pelo banco e RLS |

Tabelas append-only (UPDATE/DELETE revogados para o papel de aplicação): `audit_events`, `contract_versions`,
`equipment_events`, `financial_events`, `quote_events`, `outbox_event_failures`, `sla_clock_events`,
`stock_movements`, `visit_transitions`, `work_order_reports`, `work_order_transitions`.

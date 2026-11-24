# Runbooks

Procedimentos operacionais. Cada seção indica se foi **exercitada** (executada e conferida) ou apenas
**escrita** (procedimento documentado, ainda não executado em ambiente real).

## Deploy

*Exercitado localmente com Docker Compose; o pipeline de deploy em produção não é automatizado.*

1. Construir a imagem (`docker build --target production`), já validada pela CI (build, smoke test e análise).
2. Executar **uma vez** o serviço de preparação: `bin/db-prepare` (papel owner: migrations, privilégios do papel de
   aplicação e dados de referência). Nunca rodar migrations nos processos web.
3. Subir `web` e `worker` com a nova imagem. Conferir `/up` (liveness) e `/ready` (bancos e migrations).
4. Variáveis obrigatórias em produção: `APP_HOST`, `DB_APP_USER`, `DB_APP_PASSWORD`, chaves do Active Record
   Encryption (`ACTIVE_RECORD_ENCRYPTION_*`), `SECRET_KEY_BASE`; para métricas, `METRICS_TOKEN`.

## Backup e restauração

*Exercitado localmente em 2026-11-24 (PostgreSQL 18.7): `pg_dump --format=custom` do banco de desenvolvimento
(385 KB), restauração com `pg_restore` em banco novo em 5 s, contagens de `organizations`, `stock_movements`,
`contracts` e `plans` idênticas e as 70 políticas `tenant_isolation` preservadas. Não exercitado em produção nem
com volume real.*

Backup (diário, com retenção conforme a política da empresa):

```bash
pg_dump --format=custom --no-owner --no-privileges --file=servora_$(date +%F).dump "$DATABASE_NAME"
```

Restauração:

```bash
createdb servora_restaurado
pg_restore --no-owner --no-privileges --exit-on-error -d servora_restaurado servora_AAAA-MM-DD.dump
SERVORA_DB_ROLE=owner bin/rails db:privileges:apply   # reaplica privilégios e dados de referência
```

Conferências após restaurar: contagem das tabelas principais, políticas RLS (`SELECT count(*) FROM pg_policies`),
`bin/rails runner` com uma consulta sem contexto de tenant (deve retornar zero linhas), `/ready` respondendo 200.
Os bancos `queue`, `cache` e `cable` são recriáveis; o backup crítico é o `primary`. Arquivos anexados ficam no
armazenamento de objetos e precisam de política de versionamento ou backup próprios do provedor.

## Outbox com eventos em falha definitiva

*Exercitado em testes automatizados (`spec/services/outbox/**`).*

1. Métrica `outbox_events{status="dead"}` acima de zero ou `outbox_oldest_pending_seconds` crescendo.
2. Tela **Eventos** (perfil com `outbox_reprocess`): ver a falha registrada e a mensagem.
3. Corrigir a causa (configuração, integração indisponível) e usar **Reprocessar** (auditado). Handlers são
   idempotentes: reprocessar não duplica efeitos.

## Webhooks de saída falhando

*Exercitado em testes automatizados (`spec/services/webhooks_spec.rb`).*

1. Métrica `webhook_deliveries_total{outcome="failed"}` ou entregas com falha em **Integrações**.
2. Ver código HTTP e erro da última tentativa. "URL recusada" indica endereço interno ou não HTTPS (proteção
   contra SSRF): corrigir o endpoint.
3. Após o receptor voltar, usar **Reenviar**. O receptor deve deduplicar por `Servora-Event-Id`.

## Pagamentos sem confirmação

*Exercitado com o simulador e com o adapter do Asaas sob WebMock; não exercitado contra o Asaas real.*

1. Cobranças "Em verificação" indicam resposta perdida: o job tenta de novo consultando a referência externa antes
   de criar (nunca duplica).
2. A conciliação roda a cada 5 minutos; na tela da conta, **Consultar situação** antecipa a consulta.
3. Notificações do Asaas: conferir o token em **Integrações** e o cabeçalho `asaas-access-token` no painel do
   provedor. Notificações recebidas ficam em `inbound_webhooks` (situação `failed` exige análise do erro).

## Suspeita de vazamento entre organizações

*Escrito.*

1. Confirmar que a aplicação conecta com `DB_APP_USER` (sem `BYPASSRLS`, sem ser dono das tabelas):
   `spec/database/roles_spec.rb` descreve as consultas.
2. Conferir políticas: todas as tabelas de tenant devem ter `tenant_isolation`.
3. Buscar nos logs JSON as requisições do período pelo `request_id` e `organization_id`.
4. Revogar credenciais de API e sessões envolvidas (telas de Integrações e Segurança da conta).

## Rotação de segredos

*Escrito.* Rotacionar `SECRET_KEY_BASE` encerra sessões. Chaves do Active Record Encryption exigem migração das
chaves anteriores (`previous` na configuração) antes da troca. Tokens de API e segredos de webhook são rotacionados
pela tela de Integrações (criar novo, migrar o integrador, revogar o anterior).

## Alertas sugeridos

| Condição | Métrica |
|---|---|
| Erros 5xx acima do normal | `http_requests_errors_total` |
| Latência p95 alta | `http_request_duration_seconds` |
| Outbox atrasada | `outbox_oldest_pending_seconds > 300` |
| Eventos mortos | `outbox_events{status="dead"} > 0` |
| Fila acumulando | `jobs_ready` |
| Integração falhando | `integration_requests_total{outcome!="ok"}` |
| Consultas lentas frequentes | `db_slow_queries_total` |

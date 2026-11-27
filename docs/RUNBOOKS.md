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

## Demonstração pública

*Carga exercitada localmente em 2026-11-27 (banco novo, `bin/db-prepare --seed` completo): de 30 a 40 s em modo
de produção, dos quais 25 a 30 s de história, e de 60 a 80 s em desenvolvimento (serviço `migrate` do
`docker-compose.yml`), dos quais 55 a 65 s de história — o tempo varia com a máquina e o disco. Resultado: seis
semanas com três a cinco visitas de rotina por dia útil (cerca de quatro em média), 26 clientes, cerca de 70
equipamentos, 125 a 135 ordens e 17 orçamentos. O avanço da história (`Demo::AdvanceStoryJob`) foi exercitado em
modo de produção sobre esse banco (de 1 a 3 s por execução). O timer, o proxy e o Mailpit da instância pública
ficam fora do repositório: o procedimento abaixo está escrito, não exercitado.*

Instância dedicada que guarda apenas os dados de demonstração e é apagada e recarregada todos os dias. Nunca
ligar essas variáveis em uma instância com clientes reais: o modo de demonstração publica contas e senha na tela
de acesso, e a carga cria organizações e pessoas fictícias.

| Processo | Variáveis além das obrigatórias de produção (seção Deploy) |
|---|---|
| `web` | `SERVORA_DEMO=1`; `SEED_PASSWORD` com o mesmo valor da carga (é exibida na tela de acesso); `SERVORA_DEMO_INBOX_URL` opcional (padrão `/caixa-de-entrada`; vazio esconde o link) |
| `worker` | `SERVORA_DEMO=1` e `SEED_DEMO_ACTIVITY=1` (agendam a tarefa `demo_story_advance` e sobem o processo da fila `demo`, abaixo) |
| carga diária | `RAILS_ENV=production`, `SEED_DEMO_ACTIVITY=1`, `SERVORA_DEMO=1`, `SEED_PASSWORD`; credenciais dos papéis owner e aplicação (`DB_OWNER_*`, `DB_APP_*`) |

Proxy (na frente do `web`):

- `/caixa-de-entrada` → Mailpit **somente leitura**: interface publicada sob esse prefixo (`MP_WEBROOT=caixa-de-entrada`)
  e, no proxy, apenas `GET` e `HEAD` (bloquear `POST`, `PUT`, `PATCH` e `DELETE` da API, que apagam ou reenviam
  mensagens). O SMTP do Mailpit fica só na rede interna (`SMTP_ADDRESS` do `web` e do `worker`); todos os
  endereços da demonstração usam o domínio reservado `.test`.
- Bloquear o que deixaria uma conta compartilhada inutilizável para o próximo visitante: a verificação em duas
  etapas (`/conta/verificacao-em-duas-etapas*`; no modo de demonstração a exigência para perfis privilegiados não
  se aplica), a edição e a exclusão do cadastro (`/conta/cadastro*`) e a redefinição de senha (`/conta/senha*`,
  cujo e-mail cairia na caixa de entrada pública).

Recarga diária (timer systemd às 06:55 UTC = 03:55 em `America/Sao_Paulo`):

1. Parar `web` e `worker` (ou responder com página de manutenção).
2. Apagar e recriar os bancos: `SERVORA_DB_ROLE=owner DISABLE_DATABASE_ENVIRONMENT_CHECK=1 bin/rails db:drop`
   (primary, queue, cache e cable) e, com as variáveis da carga, `bin/db-prepare --seed`. A saída deve terminar
   com "Atividade de demonstração registrada (N s)." (N é o tempo de gravação da história); qualquer erro deixa a
   história de fora (ela grava em uma única transação) e a unidade deve falhar e alertar.
3. Esvaziar o Mailpit pela rede interna (`DELETE /api/v1/messages`), para a caixa de entrada mostrar só os
   e-mails do dia.
4. Subir `worker` e `web`. O `worker` envia logo em seguida o link do portal do orçamento que aguarda aprovação
   (Paula, Horizonte) e retoma as rotinas (varredura de SLA e avanço da história a cada 5 minutos).

O que o visitante encontra: a história só registra o que já aconteceu no instante da carga (detalhes em
`docs/DEMO.md`, "Dados pré-carregados"). Com a recarga às 03:55, as visitas de hoje começam o dia agendadas; ao
longo do dia a tarefa abaixo as executa nos horários previstos, e o visitante também pode agir por conta própria
(entrar como Diego, Minha agenda). Para outro horário de recarga basta mudar o timer: a história se ajusta ao
instante da execução, inclusive em fins de semana e feriados.

### História ao longo do dia

A tarefa recorrente `demo_story_advance` (`Demo::AdvanceStoryJob`, fila `demo`, a cada 5 minutos) aplica os
eventos de hoje cujo horário já passou desde a carga — deslocamento e início das visitas, checklist, materiais,
conclusão, cobrança, o Pix das 09:50, a triagem do pedido do portal às 10:15, a chegada e a reserva do relé às
11:10–11:15, o pedido novo das 14:10, o pagamento da conta vencida às 14:20, a espera da Clínica e o cancelamento
da visita dela às 16:20–16:25, o retorno da câmara fria agendado às 17:40 — com as mesmas definições da carga
(`db/seeds/support/demo_activity`) e no horário de cada evento (nunca no futuro). O que muda ao longo do dia está
em `docs/DEMO.md`, "O que muda ao longo do dia".

- **Só no modo de demonstração.** A entrada só existe em `config/recurring.yml` quando o `worker` sobe com
  `SERVORA_DEMO=1` e `SEED_DEMO_ACTIVITY=1` (em desenvolvimento `SEED_DEMO_ACTIVITY` já vale `1`), e o job confere
  as duas variáveis a cada execução: em qualquer outra instância ele não faz nada.
- **Uma vez cada evento.** Cada evento deixa a própria marca nos registros que grava (horários da visita,
  diagnóstico, instante de criação de itens, contas e reservas, chaves de idempotência de consumos, pagamentos e
  entradas de estoque); uma execução interrompida é retomada pela seguinte, e duas execuções simultâneas não se
  sobrepõem (trava consultiva por organização).
- **O visitante tem precedência.** Se um visitante já iniciou, concluiu ou cancelou uma visita, concluiu ou
  faturou a ordem ou quitou a conta, o evento e os seguintes da mesma ordem são pulados, sem erro. Se ele deixou
  um item aguardando a autorização do cliente, a ordem não é concluída nem faturada; se pôs o técnico em outra
  visita (em deslocamento ou em andamento), o técnico não sai para a próxima. Esses passos esperam em silêncio e
  são reavaliados a cada execução. Um evento que falhe mesmo assim é desfeito sozinho e registrado no log
  (`demo.story_event_skipped`). Cada execução com eventos aplicados registra `demo.story_advanced`.
- **Só no dia da carga.** Entre 00:00 e a recarga das 03:55 (ou num dia em que a recarga falhou), a história é
  de outro dia e nada é aplicado.
- **Calendário fixo.** A história conta seus dias úteis com os feriados e o expediente que a carga grava
  (`Seeds::HOLIDAYS` e `Seeds::SHIFTS_SLA`), não com a tabela de feriados: um feriado cadastrado por um visitante
  muda os prazos de SLA dali em diante, como em produção, mas não desloca os eventos do dia.

- **Processo próprio.** Os eventos são gravados com o relógio do processo movido para o instante de cada um,
  por alguns milissegundos (`travel_to`), e isso vale para todas as threads do processo. Por isso o job usa a
  fila `demo`, que só um worker de uma thread atende: com `SERVORA_DEMO=1`, `config/queue.yml` acrescenta esse
  processo (`queues: [demo]`, `threads: 1`, `processes: 1`) ao lado do worker das demais filas, que não lista
  `demo`. Nenhum outro job, nem o heartbeat de outro processo, lê o relógio movido. Sem `SERVORA_DEMO=1` o
  processo não existe e a fila fica vazia (a tarefa também não é agendada).
- **Conferência.** Com o `worker` no ar, a tabela `solid_queue_processes` tem dois processos do tipo `Worker`,
  um deles com `"queues":"demo"` em `metadata`; `solid_queue_recurring_tasks` tem `demo_story_advance` na fila
  `demo`.
- **Heartbeat do próprio processo.** O único efeito possível do relógio movido é um heartbeat do processo da fila
  `demo` gravado com um horário do passado, se ele cair num desses milissegundos; o heartbeat seguinte (60 s
  depois) corrige. No pior caso o processo é dado como perdido e substituído, e a execução seguinte retoma de
  onde a história parou (cada evento é aplicado uma única vez).

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

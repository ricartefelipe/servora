# Registro de decisões

Formato: contexto, decisão e consequências. Decisões substituídas permanecem registradas com o
status atualizado.

## DEC-001 — Monólito modular Rails 8.1 com Hotwire

- **Contexto**: produto B2B com fluxos transacionais fortes (orçamento → ordem → estoque → financeiro)
  e equipe pequena.
- **Decisão**: uma aplicação Rails 8.1.4.1 (Ruby 4.0.10), renderização no servidor com Turbo e Stimulus,
  importmap e Tailwind CSS v4 sem toolchain Node.
- **Consequências**: deploy único, transações locais entre módulos; os limites entre contextos são
  mantidos por namespaces e convenções (ver `ARQUITETURA.md`), não por processos separados.

## DEC-002 — PostgreSQL 18 com `db/structure.sql`

- **Contexto**: a integridade depende de RLS, `EXCLUDE USING gist`, funções `SECURITY DEFINER`,
  triggers e chaves estrangeiras compostas, que o formato Ruby do schema não representa.
- **Decisão**: `schema_format = :sql` no banco principal; bancos de fila, cache e cable mantêm schema Ruby.
  Chaves primárias UUIDv7 geradas pelo banco (`uuidv7()`, nativo no PostgreSQL 18).
- **Consequências**: a CI reconstrói o banco a partir de `structure.sql` e valida que as migrations
  produzem exatamente o mesmo dump. É necessário cliente PostgreSQL 18 (`psql`/`pg_dump`) nos ambientes
  que executam tarefas de banco; a imagem Docker instala o cliente do repositório PGDG.

## DEC-003 — Dois papéis de banco: owner e aplicação

- **Contexto**: RLS não se aplica a superusuários, ao dono da tabela (sem `FORCE`) nem a papéis com `BYPASSRLS`.
- **Decisão**: `servora_owner` (CREATEDB, dono do schema, executa migrations) e `servora_app`
  (LOGIN, sem superuser, sem BYPASSRLS, sem CREATEDB, não é dono de nada). Os processos web e worker usam
  apenas `servora_app`. Privilégios são reaplicados por `db:privileges:apply` porque o dump do Rails
  omite `GRANT`s. Tabelas de histórico ficam sem `UPDATE`/`DELETE` para o papel de aplicação.
- **Consequências**: migrations exigem `SERVORA_DB_ROLE=owner` (encapsulado em `bin/db-prepare`).
  A suíte de testes conecta como `servora_app` e uma conexão de manutenção (owner) limpa apenas os
  dados de exemplos com commit real.

## DEC-004 — Contexto de tenant transacional (`set_config(..., true)`)

- **Contexto**: conexões são reutilizadas pelo pool; um `SET` de sessão vazaria entre requisições.
- **Decisão**: o contexto é gravado com `set_config('servora.organization_id', ..., true)` dentro de uma
  transação que envolve toda a ação (incluindo renderização de views, para relações avaliadas tardiamente).
  A função `servora_current_organization_id()` converte ausência ou string vazia em `NULL`, que nunca
  satisfaz as policies. O tenant vem da sessão e é revalidado contra o vínculo ativo a cada requisição.
- **Consequências**: sem contexto não há acesso; chamadas HTTP externas não ocorrem dentro dessa
  transação (são feitas por jobs, em transações curtas antes e depois da chamada).

## DEC-005 — Resolução de tokens por funções `SECURITY DEFINER` estreitas

- **Contexto**: convites, links do portal, credenciais de API e webhooks chegam sem contexto de tenant.
- **Decisão**: funções específicas (`servora_resolve_*`) recebem apenas o digest do token e devolvem
  somente o `organization_id`. Execução restrita ao papel de aplicação. Depois disso, o registro é
  carregado normalmente sob RLS.
- **Consequências**: o papel de aplicação nunca precisa de bypass; cada função é auditável e testada.

## DEC-006 — Fila, cache e cable em bancos separados (Solid Queue, Solid Cache, Solid Cable)

- **Contexto**: o produto não exige Redis; a fila precisa sobreviver a reinícios.
- **Decisão**: bancos `*_queue`, `*_cache` e `*_cable` separados do principal. Solid Cache é usado para
  contadores de rate limiting compartilhados entre processos; não há cache de dados de negócio por padrão.
- **Consequências**: enfileirar um job não é atômico com a transação de negócio — por isso existe o
  Transactional Outbox (DEC-008).

## DEC-007 — Sem variantes e previews do Active Storage

- **Contexto**: variantes exigem libvips e criam rotas e arquivos derivados que precisam da mesma
  autorização que o original.
- **Decisão**: `variant_processor = :disabled`, rotas padrão do Active Storage desligadas
  (`draw_routes = false`); downloads passam por um controller que autoriza registro e organização.
  Fotos são reduzidas no próprio dispositivo antes do envio.
- **Consequências**: menos dependências nativas na imagem; miniaturas usam o arquivo original com
  dimensionamento por CSS, limitado pelo tamanho máximo de upload.

## DEC-008 — Transactional Outbox no banco principal

- **Contexto**: a fila está em outro banco (DEC-006).
- **Decisão**: eventos de negócio são gravados em `outbox_events` na mesma transação. Um despachante
  reivindica lotes com lease (`FOR UPDATE SKIP LOCKED` dentro de função `SECURITY DEFINER`), executa os
  handlers idempotentes, registra falhas e aplica retentativas limitadas com backoff.
- **Consequências**: entrega pelo menos uma vez; handlers deduplicam por identificador de evento.
  Não há promessa de execução exatamente uma vez.

## DEC-009 — Ruby 4.0.10

- **Contexto**: a análise do Brakeman apontou vulnerabilidade crítica (CVE-2026-132825) no Ruby 4.0.9.
- **Decisão**: fixar Ruby 4.0.10 em `.ruby-version` e na imagem base `ruby:4.0.10-slim-trixie`.
- **Consequências**: ambientes locais precisam instalar 4.0.10.

## DEC-010 — Ações de CI fixadas por SHA e ferramentas por versão

- **Decisão**: actions referenciadas por SHA de commit com o número da versão em comentário; Trivy e
  Gitleaks executados por imagens com tag de versão exata. Nenhuma referência `latest`.
- **Consequências**: atualizações são feitas explicitamente (Dependabot abre PRs para `develop`).

## DEC-011 — Registro de sessões no servidor

- **Contexto**: cookies de sessão não podem ser revogados individualmente pelo servidor.
- **Decisão**: cada login cria uma linha em `user_sessions`; hooks documentados do Warden validam a linha a
  cada requisição e a revogam no logout. Troca e redefinição de senha encerram as demais sessões.
  `rememberable` não é usado para não criar um caminho de autenticação paralelo.
- **Consequências**: uma consulta adicional por requisição autenticada; `last_seen_at` é atualizado no
  máximo a cada 5 minutos.

## DEC-012 — MFA obrigatório para perfis privilegiados com prazo de adesão

- **Decisão**: TOTP (devise-two-factor, segredo cifrado com Active Record Encryption) e 10 códigos de
  recuperação armazenados com hash. Login em duas etapas, com tentativas de código contando para o
  bloqueio do Devise. Proprietário, administrador e financeiro têm prazo configurável para ativar.
- **Consequências**: a organização pode desligar a exigência; a interface sinaliza o prazo restante.

## DEC-013 — Token de convite gerado na entrega

- **Decisão**: o banco guarda somente o digest SHA-256; o token em claro é gerado no momento do envio do
  e-mail e nunca é serializado em jobs. Reenviar invalida o link anterior.

## DEC-014 — Paginação por offset com limite rígido

- **Decisão**: objeto `Pagination` próprio (máximo de 100 itens por página, sem `COUNT(*)`), em vez de
  uma dependência externa. Suficiente para listas administrativas; a API usará paginação por cursor.

## DEC-015 — Rate limiting nativo do Rails com Solid Cache

- **Decisão**: `rate_limit` do Action Controller em login, segundo fator, cadastro, recuperação de senha,
  confirmação, desbloqueio, convites e criação de organização. O contador fica no Solid Cache
  compartilhado entre processos (memória nos testes).

## DEC-016 — Jobs concluídos não são preservados

- **Decisão**: `solid_queue.preserve_finished_jobs = false`, para que argumentos de jobs (por exemplo,
  tokens de e-mails do Devise) não permaneçam no banco da fila após a execução.

## DEC-017 — Tempo de parede nas verificações da outbox

- **Contexto**: `now()` no PostgreSQL é o início da transação; eventos gravados com o relógio da aplicação
  poderiam parecer "no futuro" para a reivindicação.
- **Decisão**: a função de claim usa `clock_timestamp()` para vencimento e lease.

## DEC-018 — `structure.sql` regenerado a partir de migrations reais

- **Contexto**: no Rails 8, `db:migrate` em banco vazio carrega o schema existente; o texto de algumas
  constraints muda quando o dump é recarregado.
- **Decisão**: `bin/db-structure` move o dump, executa todas as migrations num banco temporário e valida
  rollback e recarga; a CI executa `bin/db-structure --check`. Constraints de domínio usam
  `add_inclusion_constraint`, cuja forma canônica é estável.

## DEC-019 — Arredondamento monetário e precisão

- **Decisão**: valores em BRL com `decimal(14,2)` e arredondamento comercial (half up), igual ao
  `round(numeric, 2)` do PostgreSQL usado nas constraints; quantidades `decimal(14,3)`; custos unitários
  `decimal(14,4)`. A camada `Pricing` (regras puras) recusa `Float`.
- **Consequências**: o total de cada linha é verificado pelo banco (`line_total = round(qtd × preço, 2) − desconto`).

## DEC-020 — Versões de orçamento imutáveis por trigger

- **Decisão**: além das regras nos casos de uso, triggers rejeitam alterações em itens, totais, condições,
  snapshot e dados da decisão de versões que saíram de `draft`.
- **Consequências**: nem um bug na aplicação nem um acesso direto com o papel de aplicação alteram o que o
  cliente aprovou.

## DEC-021 — Portal com concessão de uso único trocada por sessão

- **Decisão**: link por e-mail (uso único, 72 h) consumido por POST; sessão própria do portal (12 h) com
  revalidação a cada requisição. Sem senhas para contatos de clientes nesta versão.
- **Consequências**: links pré-visualizados por clientes de e-mail não consomem o acesso; revogar o contato ou
  desabilitar o portal encerra a sessão na próxima requisição.

## DEC-022 — Carregamento de registros únicos por relação explícita

- **Contexto**: registros carregados por um `has_many` da organização são marcados pelo Rails como estritos
  (suspeita de N+1), mesmo em buscas de um único registro.
- **Decisão**: listagens partem das associações da organização (detecção de N+1 ativa); buscas de um registro
  usam `tenant_relation(Model)` (`where(organization_id: …)`) combinado com `policy_scope`.

## DEC-023 — Reservas por técnico com exclusion constraint

- **Decisão**: uma linha por técnico e visita (ou ausência) com `tstzrange` semiaberto e
  `EXCLUDE USING gist` filtrado por `status = 'active'`. O deslocamento compõe o intervalo bloqueado.
- **Consequências**: proteção contra reserva dupla independe da aplicação; equipes são reservadas em uma única
  transação; a interface explica o conflito consultando as reservas que colidem.

## DEC-024 — Linha do tempo sem estilos inline

- **Decisão**: a agenda diária usa CSS Grid de 64 colunas (15 min) com classes `col-start-*`/`col-span-*`
  geradas pelo Tailwind (`@source inline`), em vez de `style` com porcentagens, preservando a CSP sem
  `unsafe-inline`. Reagendamento é feito por formulário (alternativa acessível a arrastar e soltar).

## DEC-025 — Estoque como razão append-only com saldo protegido por trigger

- **Contexto**: o saldo precisa ser consultado rapidamente e nunca pode divergir do histórico, mesmo com
  concorrência ou acesso direto com o papel de aplicação.
- **Decisão**: saldo materializado em `stock_balances`, alterado apenas pelo `Inventory::Ledger` junto com uma
  movimentação append-only que registra o saldo resultante. Um trigger valida que cada alteração corresponde
  a uma movimentação nova, do mesmo depósito e item, com quantidade compatível com o tipo. Locks sempre na
  ordem ordem de serviço → reserva/consumo → saldos ordenados.
- **Alternativas**: recalcular o saldo somando movimentações (consulta cara e sujeita a corrida sem lock de
  agregação); confiar apenas na aplicação (não protege contra acessos diretos ou bugs).
- **Consequências**: histórico auditável por construção, disputa pela última unidade resolvida pelo lock da
  linha de saldo, ausência de deadlocks entre transferências cruzadas.

## DEC-026 — Aba ativa lembrada por página

- **Contexto**: redirecionamentos seguidos pelo Turbo descartam o fragmento da URL, e a página voltava para a
  primeira aba após cada envio de formulário.
- **Decisão**: o controller de abas guarda apenas a chave da última aba escolhida por caminho em
  `sessionStorage` (prefixo `servora:`), usada quando a URL não tem fragmento; o expurgo de dados locais na
  troca de contexto também limpa essas chaves.

## DEC-027 — Posição da conta como valor puro com constraints espelhadas

- **Decisão**: contas guardam valor, descontos, pago e estornado; a situação deriva desses valores em
  `Receivables::Position` e as mesmas regras existem como constraints. Todo uso de caso trava a conta e grava
  um evento financeiro append-only.
- **Consequências**: nenhuma combinação inválida (pagamento acima do saldo, cancelamento com dinheiro retido)
  persiste, mesmo por acesso direto; o histórico explica cada centavo.

## DEC-028 — Integração de pagamentos fora de transações, guiada por referência externa

- **Contexto**: o provedor pode processar uma requisição cuja resposta se perde; repetir cegamente gera
  cobrança duplicada, e chamadas de rede dentro de transações seguram locks.
- **Decisão**: a cobrança nasce `pending` com uma referência externa estável, gravada junto com o evento da
  outbox. O job envia fora de transação; após qualquer tentativa anterior consulta o provedor pela referência
  antes de criar. Falhas são classificadas em não enviada, ambígua e recusada. Confirmações registram o
  pagamento com chave de idempotência derivada da cobrança. Conciliação periódica cobre confirmações perdidas.
- **Consequências**: uma cobrança por referência, sem locks durante I/O; o simulador reproduz os cenários de
  forma determinística para testes e demonstração.

## DEC-029 — Ocorrências preventivas calculadas a partir da âncora, com identidade (plano, sequência)

- **Contexto**: calcular cada data a partir da anterior acumula o ajuste de fim de mês (31 → 28 → 28…);
  agendadores repetidos ou concorrentes podem duplicar ordens.
- **Decisão**: datas sempre derivadas da âncora; mudanças de calendário reancoram na próxima sequência; cada
  ocorrência tem identidade única `(plano, sequência)` no banco e a geração trava o plano. A recuperação após
  indisponibilidade é limitada por execução.
- **Consequências**: datas previsíveis e testáveis no domínio puro; repetir a geração é inofensivo; alterar o
  plano não reescreve o passado.

## DEC-030 — Plano preventivo sempre pertence a um contrato

- **Decisão**: o plano exige contrato (e herda o cliente dele). A cobertura, os limites e a suspensão do
  contrato governam a geração das ocorrências.
- **Consequências**: uma única fonte para vigência e suspensão; manutenção preventiva avulsa é modelada como
  um contrato sem mensalidade.

## DEC-031 — Relógios de SLA com consumo acumulado e deduplicação por reivindicação

- **Contexto**: prazos precisam pausar e retomar sem recalcular a história, e alertas não podem se repetir
  quando varreduras se sobrepõem.
- **Decisão**: cada relógio guarda o tempo útil consumido até a última pausa e, enquanto corre, o instante de
  início do trecho, o vencimento e o instante do alerta. Pausar soma o trecho; retomar recalcula vencimento a
  partir do restante. Alertas são reivindicados com atualização condicional na própria linha antes de publicar.
- **Alternativas**: recalcular a partir do histórico a cada consulta (custo e complexidade); travar uma linha
  global de agendamento (serializa organizações sem necessidade).
- **Consequências**: consultas de risco e estouro são simples (`due_at`, `warn_at`); qualquer número de
  varreduras concorrentes notifica uma vez.

## DEC-032 — Active Storage com organização atribuída pelo banco

- **Contexto**: as tabelas padrão do Active Storage não têm organização e ficariam fora do RLS.
- **Decisão**: criar as tabelas com `organization_id NOT NULL DEFAULT servora_current_organization_id()`, política
  de isolamento e chaves compostas entre anexos e blobs; desligar rotas, análises e variantes; servir arquivos
  só por controllers autorizados.
- **Consequências**: nenhum código precisa lembrar de preencher a organização; criar blob fora de um contexto
  de tenant falha. Uploads para o armazenamento ocorrem dentro da transação da requisição (sem locks de linha
  mantidos nesse momento).

## DEC-033 — PDFs gerados sob demanda a partir de dados congelados

- **Decisão**: não armazenar PDFs; gerar a partir do snapshot da versão do orçamento e dos dados da versão do
  relatório, ambos imutáveis.
- **Consequências**: sem arquivos órfãos nem divergência entre registro e documento; o custo é gerar a cada
  download (documentos pequenos).


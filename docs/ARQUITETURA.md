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

## Identidade, organizações e permissões

- `User` é uma identidade global (Devise). Dados por organização ficam em `Membership`
  (papel, situação, custo/hora). Um usuário pode ter vínculos em várias organizações.
- A organização ativa fica na sessão, mas **cada requisição** relê o vínculo ativo do usuário dentro do
  contexto RLS (`TenantController#within_organization`). Vínculo ausente ou desativado encerra o acesso
  imediatamente, inclusive em sessões já abertas.
- Trocar de organização rotaciona o identificador da sessão e limpa os rascunhos locais do dispositivo
  (`local_context_controller.js`, chave derivada por HMAC de usuário + organização).
- Sessões autenticadas têm registro no servidor (`user_sessions`): logout, troca de senha, redefinição e
  "encerrar demais sessões" revogam os registros; a próxima requisição com cookie revogado é recusada.
- MFA (TOTP + códigos de recuperação) é obrigatório para proprietário, administrador e financeiro, com
  prazo de adesão configurável (`MFA_ENROLLMENT_GRACE_DAYS`, padrão 7 dias); depois disso o acesso à
  organização é bloqueado até a ativação.
- Convites: o token em claro só existe no e-mail. A entrega rotaciona o token (`Invitations::Deliver`),
  invalidando links anteriores. Aceite exige POST do usuário autenticado com o mesmo e-mail; uso único
  garantido por lock da linha e índice único de vínculo.

### Matriz de permissões

Gerada a partir de `Authorization::Permissions` (o teste `spec/unit/authorization/permission_matrix_spec.rb`
falha se este quadro divergir do código).

| Permissão | Proprietário | Administrador | Coordenador | Atendente | Técnico | Financeiro | Auditor |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| Configurar a organização | ✔ | ✔ | — | — | — | — | — |
| Ver equipe | ✔ | ✔ | ✔ | — | — | — | ✔ |
| Gerenciar membros e convites | ✔ | ✔ | — | — | — | — | — |
| Gerenciar assinatura do Servora | ✔ | — | — | — | — | — | — |
| Ver clientes e locais | ✔ | ✔ | ✔ | ✔ | — | ✔ | ✔ |
| Gerenciar clientes e locais | ✔ | ✔ | ✔ | ✔ | — | — | — |
| Ver equipamentos | ✔ | ✔ | ✔ | ✔ | ✔ | — | ✔ |
| Gerenciar equipamentos | ✔ | ✔ | ✔ | ✔ | — | — | — |
| Ver catálogo (preço de venda) | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| Gerenciar catálogo | ✔ | ✔ | ✔ | — | — | — | — |
| Ver custos internos e margens | ✔ | ✔ | — | — | — | ✔ | ✔ |
| Ver orçamentos | ✔ | ✔ | ✔ | ✔ | — | ✔ | ✔ |
| Criar, versionar e enviar orçamentos | ✔ | ✔ | ✔ | ✔ | — | — | — |
| Ver todas as ordens de serviço | ✔ | ✔ | ✔ | ✔ | — | ✔ | ✔ |
| Criar e gerenciar ordens | ✔ | ✔ | ✔ | ✔ | — | — | — |
| Executar ordens atribuídas | ✔ | ✔ | — | — | ✔ | — | — |
| Cancelar ordens | ✔ | ✔ | ✔ | — | — | — | — |
| Reabrir ordens concluídas | ✔ | ✔ | ✔ | — | — | — | — |
| Autorizar serviços adicionais | ✔ | ✔ | ✔ | — | — | — | — |
| Ver agenda | ✔ | ✔ | ✔ | ✔ | ✔ | — | ✔ |
| Agendar e despachar | ✔ | ✔ | ✔ | ✔ | — | — | — |
| Ver contratos | ✔ | ✔ | ✔ | ✔ | — | ✔ | ✔ |
| Gerenciar contratos | ✔ | ✔ | ✔ | — | — | — | — |
| Gerenciar planos preventivos | ✔ | ✔ | ✔ | — | — | — | — |
| Ver estoque | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| Movimentar estoque | ✔ | ✔ | ✔ | — | — | — | — |
| Ajustar saldos de estoque | ✔ | ✔ | — | — | — | — | — |
| Ver financeiro | ✔ | ✔ | — | — | — | ✔ | ✔ |
| Gerenciar recebíveis e cobranças | ✔ | ✔ | — | — | — | ✔ | — |
| Conceder descontos | ✔ | ✔ | — | — | — | ✔ | — |
| Estornar pagamentos | ✔ | ✔ | — | — | — | ✔ | — |
| Ver relatórios | ✔ | ✔ | ✔ | — | — | ✔ | ✔ |
| Gerenciar integrações e API | ✔ | ✔ | — | — | — | — | — |
| Ver auditoria | ✔ | ✔ | — | — | — | — | ✔ |
| Reprocessar eventos com falha | ✔ | ✔ | — | — | — | — | — |

Escopos adicionais aplicados pelas policies:

- Técnicos enxergam apenas os registros atribuídos a eles (ordens, visitas e agenda próprias).
- Somente proprietários concedem ou alteram o papel de proprietário; ninguém altera o próprio acesso.
- A organização sempre mantém ao menos um proprietário ativo (`Memberships::OwnerGuard`, com lock).

## Clientes, locais e equipamentos

- `Customer` (PF/PJ, CPF/CNPJ validados e únicos por organização) possui vários `ServiceLocation` e
  `CustomerContact` (acompanha serviços, aprova orçamentos, acesso ao portal).
- `Equipment` referencia `(organization_id, customer_id, service_location_id)` em
  `service_locations (organization_id, customer_id, id)`: o banco garante que o local pertence ao cliente
  proprietário, além da validação no model.
- Mudança de local e transferência de proprietário passam por `EquipmentLifecycle::Relocate`, com bloqueio
  otimista (`lock_version`) e registro em `equipment_events` (append-only).
- Equipamentos com histórico de atendimento não são excluídos: apenas arquivados. A exclusão existe só para
  cadastros feitos por engano e é bloqueada também por chaves estrangeiras restritivas.

## Catálogo e orçamentos

- Catálogo com serviços e peças, preço de venda (público aos papéis operacionais) e custo (apenas com
  `costs_view`). Alterações no catálogo não afetam orçamentos: itens copiam descrição, unidade, preço e custo.
- Orçamentos têm número sequencial por organização e ano (`ORC-AAAA-NNNNN`, alocação atômica com
  `INSERT … ON CONFLICT DO UPDATE … RETURNING`) e versões.

### Máquina de estados da versão de orçamento

```
draft ──enviar──▶ sent ──▶ approved ──┐
                    │──▶ rejected ────┼──(nova versão enviada)──▶ superseded
                    └──▶ expired ─────┘
```

- Ao enviar, a versão recebe um **snapshot** (dados do cliente, local, itens, totais e condições, sem custos)
  e o **digest SHA-256** do JSON canônico. Triggers impedem qualquer alteração de itens, totais, condições,
  snapshot e decisão de versões que saíram de `draft`.
- A decisão exige: versão vigente, situação `sent`, validade não expirada no fuso da organização, digest igual
  ao conteúdo apresentado e contato autorizado (`can_approve`) do mesmo cliente. Registra canal, contato,
  membro que registrou (canais internos), IP, agente e observação. É uma confirmação eletrônica simples, não
  uma assinatura certificada.
- Mudança após envio ou aprovação: nova versão (cópia dos itens) e nova decisão do cliente.
- A conversão em ordem de serviço usa a versão aprovada (feature de ordens de serviço).

## Ordens de serviço

### Máquina de estados da ordem

```
open ─▶ awaiting_approval ─▶ approved ─▶ scheduled ─▶ in_progress ─▶ completed ─▶ reopened
                                │            ▲   │         │  ▲                     │
                                └────────────┘   │         ▼  │                     ▼
                                    waiting_parts / waiting_customer        (scheduled, in_progress,
                                                                              completed, canceled)
canceled: a partir de qualquer estado não concluído (motivo obrigatório)
```

- Transições inválidas são recusadas (`WorkOrders::States`) e toda mudança fica em `work_order_transitions`
  (append-only, com ator e motivo). Visitas têm máquina própria: concluir uma visita não conclui a ordem.
- Conclusão formal (escritório) exige checklist obrigatório respondido, diagnóstico, solução, nenhuma visita em
  andamento e nenhum serviço adicional pendente de autorização. Cada conclusão grava um relatório versionado
  (`work_order_reports`, append-only, com digest); reabrir não apaga relatórios nem execução anterior.
- Conversão do orçamento: `INSERT … ON CONFLICT DO NOTHING` no índice único `(organization_id, quote_version_id)`;
  sob concorrência a requisição perdedora aguarda o commit da vencedora e devolve a mesma ordem. Itens do
  orçamento entram como autorizados (com a evidência da aprovação).
- Itens adicionais entram como pendentes e só são cobráveis após autorização registrada (contato, canal e membro).
- Equipamentos da ordem pertencem ao cliente da ordem (FK composta). Checklist é copiado do tipo de serviço
  na abertura; mudanças posteriores no tipo não afetam ordens abertas.
- Técnicos veem apenas ordens atribuídas (e os equipamentos delas), executam checklist e registro técnico, sem
  ver preços ou custos; a conclusão formal e o cancelamento são ações do escritório.

## Agenda e despacho

- `technician_allocations` é a fonte de verdade do tempo do técnico: visitas e ausências ocupam o intervalo
  **semiaberto** `[início, término + deslocamento)` (`tstzrange`, checagem de limites no banco).
- `EXCLUDE USING gist (organization_id WITH =, membership_id WITH =, period WITH &&) WHERE status = 'active'`
  impede reservas sobrepostas mesmo com dois coordenadores agendando no mesmo instante (spec com duas
  conexões e espera de lock observada em `pg_stat_activity`).
- Visita de equipe: todas as reservas são inseridas no mesmo savepoint, em ordem de id; conflito em qualquer
  integrante desfaz tudo. Reagendamento libera e recria reservas no mesmo savepoint (conflito mantém a original).
- Horário de trabalho semanal por técnico (fuso da organização) é verificado no caso de uso; ausências usam a
  mesma constraint das visitas.
- Sugestão de técnicos: filtra por competências exigidas pelo tipo de serviço, disponibilidade e horário;
  ordena pela menor carga do dia e pelo nome. Heurística determinística, não otimização de rotas.

### Máquina de estados da visita

```
scheduled ─▶ in_progress ─▶ completed
    ├──────▶ canceled
    └──────▶ no_show
```

Finalizar visita não conclui a ordem; encerrar antes do previsto libera o restante da reserva (mantendo o
deslocamento após o término real).

## Estoque

Razão (ledger) de movimentações com saldo materializado:

- `stock_movements` é **append-only** para o papel de aplicação e guarda, em cada linha, o saldo resultante
  (físico, reservado e custo médio). Tipos: entrada, reserva, liberação de reserva, consumo, devolução,
  transferência (saída/entrada, ligadas por `transfer_group_id`) e ajuste (entrada/saída).
- `stock_balances` (uma linha por depósito e item) só muda junto com uma **nova** movimentação: o trigger
  `servora_guard_stock_balance` exige que `last_movement_id` aponte para uma movimentação diferente, do mesmo
  depósito e item, cujos valores "após" coincidam com o novo saldo e cuja quantidade explique exatamente a
  variação conforme o tipo. Saldos nascem zerados; só o estoque mínimo pode mudar sem movimentação.
- Constraints garantem físico ≥ 0, reservado ≥ 0 e reservado ≤ físico (disponível = físico − reservado).
- `Inventory::Balance` (domínio puro) calcula cada operação; `Inventory::Ledger` é a única porta de escrita.

### Ordem de locks

Toda operação trava na mesma ordem: **ordem de serviço → reserva ou consumo → saldos** (ordenados por depósito
e item, `SELECT … FOR UPDATE`). Assim:

- duas ordens disputando a última unidade: a segunda espera o lock do saldo e recebe "saldo disponível
  insuficiente" (spec concorrente com espera observada em `pg_stat_activity`);
- transferências em sentidos opostos não entram em deadlock (spec com quatro conexões simultâneas);
- reserva ou consumo nunca sobrevivem a um cancelamento concorrente (a ordem é travada e revalidada).

### Idempotência

Entradas, transferências, ajustes e consumos aceitam uma chave de operação (UUID gerado ao abrir o formulário).
A chave é consultada antes da operação e protegida por índice único parcial; uma duplicata concorrente perde o
savepoint e devolve o registro vencedor. Reutilizar a chave com outros dados é recusado.

### Custos

- Custo médio móvel recalculado em entradas, devoluções, transferências recebidas e ajustes de entrada
  (4 casas, metade para cima). Saídas usam o médio vigente e não o alteram.
- O consumo grava custo unitário e total do momento (`material_consumptions`), base da margem realizada;
  devoluções retornam ao custo do consumo original e nunca superam o consumido.

### Integração com a ordem de serviço

Aba "Materiais": reservas (com liberação manual), consumo a partir de reserva ou de depósito permitido,
devolução. `work_order.canceled` e `work_order.completed` acionam
`Inventory::Handlers::ReleaseWorkOrderReservations` pela outbox.

## Anexos e documentos

- **Armazenamento isolado por organização**: as tabelas do Active Storage têm `organization_id` preenchido pelo
  banco a partir do contexto da transação (`DEFAULT servora_current_organization_id()`) e RLS; anexos referenciam
  blobs pela chave composta da organização. Um id ou chave de blob vazado não é visível em outra organização.
- Rotas padrão do Active Storage, análises, prévias e variantes estão desligadas; nenhum job do Active Storage
  roda fora do contexto de tenant (remoção síncrona).
- **Upload** (`Evidences::Upload`): limite de 15 MB e de 100 anexos por ordem; o tipo é detectado pela
  assinatura do conteúdo (JPEG, PNG, WebP, PDF), nunca pelo nome ou pelo tipo declarado; nome de arquivo
  saneado com a extensão do tipo detectado.
- **Download** apenas pelo controller da ordem, após autorização (técnicos só nas ordens atribuídas), com
  `Cache-Control: private, no-store`, `nosniff`, CSP com `sandbox` e `inline` apenas para imagens.
- Anexos de ordens encerradas são mantidos; a remoção é do escritório e auditada.
- Desenvolvimento usa disco local compartilhado entre web e worker; produção usa bucket privado compatível com
  S3, com criptografia no servidor (`config/storage.yml`).

### PDFs

- `Documents::QuoteProposal` (proposta comercial) é gerado a partir do `snapshot` congelado da versão enviada;
  `Documents::ExecutionReport` a partir dos dados de cada versão do relatório de execução. Como as fontes são
  imutáveis, o PDF de uma versão é sempre o mesmo conteúdo; o rodapé traz o início do digest para conferência.
- Ambos informam que não são nota fiscal. Gerados com Prawn sob demanda, sem armazenamento.

## SLA

- **Calendário** (`Sla::BusinessCalendar`, domínio puro): expediente semanal com até dois intervalos por dia,
  feriados e fuso da organização. Os limites de cada intervalo são montados com o relógio local do fuso; o tempo
  é medido em segundos. Políticas podem contar só no expediente ou continuamente (24×7).
- **Políticas** por prioridade: prazos de primeira resposta e resolução e percentual do prazo que dispara o
  alerta de risco. Cada relógio copia alvo, percentual e modo no início: mudar a política não move prazos já
  prometidos.
- **Relógios** (`sla_clocks`, um por ordem e métrica) são atualizados explicitamente por `WorkOrders::Create`,
  `CreateFromQuote` e `WorkOrders::Transition` dentro das mesmas transações:

| Evento da ordem | Primeira resposta | Resolução |
|---|---|---|
| Solicitação registrada | inicia | inicia |
| Agendada, em execução, aguardando peças/cliente, concluída | cumprida ou estourada | — |
| Aguardando aprovação, cliente ou peças | — | pausa (acumula o tempo útil consumido) |
| Sai da espera | — | retoma com o tempo restante |
| Concluída | — | cumprida ou estourada |
| Reaberta | — | retoma (novo segmento) com o tempo já consumido |
| Cancelada | cancelada | cancelada |

- **Alertas**: `Sla::ScanJob` (a cada 5 minutos) reivindica cada relógio com `UPDATE … WHERE warned_at IS NULL`
  (ou `breach_notified_at`) e só quem reivindica publica o evento na outbox (chave de deduplicação por relógio e
  segmento). Coordenação e técnicos atribuídos recebem notificação interna. Spec com três varreduras
  simultâneas.
- `sla_clock_events` é append-only. O painel mostra prazos estourados e em risco.

## Contratos e manutenção preventiva

### Contratos

```
draft ─▶ active ─▶ suspended ─▶ active
            └────────┴──────────▶ ended
```

- Condições (vigência, mensalidade, limite mensal de atendimentos, peças, escopo, tipos de serviço cobertos)
  são versionadas: cada alteração grava um `contract_versions` append-only com o motivo (obrigatório depois do
  rascunho). Contratos encerrados não mudam mais; encerrar desativa os planos.
- Ordens novas sem contrato informado são vinculadas ao contrato vigente do cliente que cobre o tipo de
  serviço (`Contracts::Coverage.resolve`). A cobertura de cada ordem considera vigência, tipos cobertos e o
  limite mensal contado sobre `(requested_at, id)`; a ordem mostra se está coberta ou por que não.
- FKs compostas `(organization_id, customer_id, contract_id)` impedem usar o contrato de outro cliente em
  ordens e planos; equipamentos e locais do plano também são do mesmo cliente.

### Planos preventivos

- `Preventive::Frequency` e `Preventive::Schedule` (domínio puro): a ocorrência *n* vence
  `âncora + (n − sequência_âncora) × período`, sempre calculada a partir da âncora. Dia 31 vira o último dia em
  meses curtos e volta a 31 depois; 29/02 vira 28/02 em anos comuns e volta a 29/02 nos bissextos.
- Identidade estável: `(plano, sequência)` é único no banco e cada ocorrência aponta para a ordem gerada.
- `Preventive::GenerateOccurrences` trava o plano, relê `last_sequence` e gera as ocorrências cuja janela
  (vencimento − antecedência) abriu, em ordem e no máximo 12 por execução — recuperação gradual após
  indisponibilidade do agendador, sem pular nem repetir. Spec concorrente com três geradores simultâneos.
- Alterar período, modo ou data base depois de gerar ocorrências **reancora** o plano na próxima sequência;
  ocorrências e ordens já geradas não mudam. A nova data base precisa ser posterior à última ocorrência.
- Modo "após a conclusão": a próxima ocorrência só é gerada quando a ordem anterior termina e vence um período
  depois da conclusão efetiva.
- Contrato suspenso não gera ocorrências; ao retomar, as datas que caíram na suspensão são puladas (não são
  devidas). O término do contrato limita as datas geradas.
- `Preventive::GenerateDueJob` roda diariamente (01:30) por organização ativa, um plano por transação.

## Financeiro operacional

### Contas a receber

- Uma ordem pode ter várias contas (parcelas); a soma das contas ativas nunca supera o total autorizado pelo
  cliente (itens autorizados). A emissão trava a linha da ordem.
- `Receivables::Position` (domínio puro) define as regras: saldo = (valor − descontos) − (pago − estornado);
  sem pagamento acima do saldo, sem desconto acima do saldo, sem estorno acima do pago, cancelamento apenas sem
  valor retido. Situações: em aberto, parcialmente paga, quitada, cancelada.
- Constraints repetem as regras no banco (`receivables_values`, `receivables_status_consistency`) e uma FK
  composta garante que o cliente da conta é o cliente da ordem.
- `financial_events` é append-only (pagamento, desconto, estorno, cancelamento e cada etapa da cobrança).
- Contas são travadas com `FOR NO KEY UPDATE`: inserir eventos e cobranças referenciando a conta usa
  `KEY SHARE`, que não conflita com esse lock (evita deadlock entre envio de cobrança e cancelamento).
- Pagamentos aceitam chave de operação (formulário reenviado, confirmação repetida do provedor).

### Cobranças e provedores

```
RequestCharge ──(transação: cobrança pending + evento outbox)──▶ commit
   outbox ─▶ SubmitChargeJob:
     1. claim (transação curta, lock, tentativa + 1)
     2. provedor, fora de transação:
          tentativa anterior ou situação "unknown" → consulta pela referência externa
          não encontrada → cria a cobrança com a referência
     3. registra o resultado (transação curta)
        recusa → failed · resposta perdida → unknown + nova tentativa · confirmada → ConfirmCharge
ConfirmCharge (idempotente: chave "charge:<id>") ─▶ RegisterPayment
ReconcileJob (a cada 5 min) ─▶ SyncChargeJob para cobranças aguardando pagamento ou em verificação
```

- Classificação de falhas do adapter: **não enviado** (conexão recusada, timeout de conexão, 429: repetir é
  seguro), **ambíguo** (timeout de leitura, 5xx: consultar antes de repetir) e **recusado** (4xx: definitivo).
- No máximo uma cobrança em andamento por conta (índice único parcial). Cancelar a conta cancela a cobrança
  localmente e, após o commit, no provedor.
- **Simulador** (padrão): sem rede; valores terminados em ,66 são recusados; em ,13 a primeira resposta se
  perde, mas o provedor simulado guardou a cobrança, que é encontrada pela referência na nova tentativa; a
  confirmação é acionada por "Simular pagamento".
- **Asaas (sandbox)**: `ASAAS_BASE_URL` (padrão `https://api-sandbox.asaas.com/v3`), chave por organização
  criptografada com Active Record Encryption e nunca devolvida à interface. Clientes são associados pela
  referência externa (id do cliente no Servora). Coberto por specs com WebMock; **não exercitado contra o
  sandbox real** por falta de credencial neste ambiente. Confirmação por webhook será adicionada junto com o
  módulo de webhooks de entrada; até lá, a conciliação periódica confirma os pagamentos.

### Margem

`WorkOrderFinancialsQuery`: prevista = itens autorizados × custo unitário estimado; realizada = faturado
(contas ativas, líquido de descontos) − material ao custo do consumo − mão de obra ao custo/hora do
apontamento − despesas. Faturado, recebido e margem são exibidos separadamente; margens apenas com
`costs_view`.

## Portal do cliente

- Acesso por concessão de uso único enviada por e-mail (72 h, finalidade registrada, revogável). O GET apenas
  mostra a confirmação; o POST consome a concessão e cria uma **sessão de portal** (12 h, revogável) em cookie
  assinado HttpOnly e SameSite=Lax, separada das sessões da equipe.
- Tokens nunca ficam no banco ou em argumentos de jobs: apenas digests; o token em claro é gerado no envio.
- Funções `SECURITY DEFINER` resolvem somente o `organization_id` a partir do digest; sessão e contato são
  carregados sob RLS e revalidados a cada requisição (contato ativo com portal habilitado, cliente ativo).
- Toda consulta do portal parte de `customer_scope` (cliente do contato) além do RLS.
- Funções: propostas (decisão e PDF da versão), **chamados** (o contato abre um pedido que vira ordem de serviço
  com origem portal, em análise, e a equipe é notificada pela outbox; limite de 5 por hora), acompanhamento das
  ordens e das visitas, relatórios de execução em PDF, equipamentos com histórico e cobranças com o link de
  pagamento da cobrança ativa (sem custos, observações internas ou preços de itens adicionais).
- A autoria da ordem é garantida no banco: membro da equipe **ou** contato do mesmo cliente (chave composta).
- Nenhuma alteração de estado ocorre em GET.

## Consistência assíncrona (Transactional Outbox)

A fila (Solid Queue) usa outro banco; enfileirar um job não é atômico com a transação de negócio.
Por isso, todo efeito assíncrono nasce como linha em `outbox_events`, gravada na mesma transação:

```
caso de uso ──(mesma transação)──▶ outbox_events (pending)
                                      │
   Outbox::DispatchJob (a cada 10 s e após commits) ── servora_claim_outbox_events()
                                      │   FOR UPDATE SKIP LOCKED + lease (locked_until)
                                      ▼
   contexto do tenant: handlers idempotentes ──▶ jobs (fora de transação) ──▶ ack se o lease ainda é nosso
                                      │
                         falha ──▶ outbox_event_failures + retentativa com backoff ou "dead"
```

| Situação | Comportamento |
|---|---|
| Commit ok, enqueue pós-commit falha | Evento continua `pending`; o despachante recorrente o processa |
| Worker morre durante o processamento | Lease expira; outro worker reivindica; ack tardio do primeiro é recusado |
| Evento processado duas vezes | Handlers idempotentes (ex.: notificação única por destinatário e evento) |
| Falha transitória | Nova tentativa com backoff exponencial (15 s → 1 h) até `max_attempts` |
| Falha permanente ou tentativas esgotadas | `dead`, com histórico; reprocessamento manual autorizado e auditado |

Garantia: entrega **pelo menos uma vez**. Não há promessa de exatamente uma vez; a deduplicação é
responsabilidade de cada handler e de cada job (chaves únicas e verificações de estado).

Notificações em tempo real usam streams Turbo por vínculo (`NotificationsChannel`): além da assinatura do
nome do stream, a inscrição só é aceita se o vínculo pertencer ao usuário conectado e estiver ativo.
Nada é transmitido para a organização inteira.

## Processos

| Processo | Comando | Observações |
|---|---|---|
| Web | `bin/rails server` | Puma; nunca executa migrations. |
| Worker | `bin/jobs` | Solid Queue (fila em banco próprio) e tarefas recorrentes (`config/recurring.yml`). |
| Release | `bin/db-prepare` | Executado uma vez por deploy com o papel owner. |

## Bancos

| Banco | Conteúdo | Schema |
|---|---|---|
| `servora_<env>` | Dados de negócio (RLS) | `db/structure.sql` |
| `servora_<env>_queue` | Solid Queue | `db/queue_schema.rb` |
| `servora_<env>_cache` | Solid Cache (rate limiting) | `db/cache_schema.rb` |
| `servora_<env>_cable` | Solid Cable | `db/cable_schema.rb` |

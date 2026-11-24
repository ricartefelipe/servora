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

## Portal do cliente

- Acesso por concessão de uso único enviada por e-mail (72 h, finalidade registrada, revogável). O GET apenas
  mostra a confirmação; o POST consome a concessão e cria uma **sessão de portal** (12 h, revogável) em cookie
  assinado HttpOnly e SameSite=Lax, separada das sessões da equipe.
- Tokens nunca ficam no banco ou em argumentos de jobs: apenas digests; o token em claro é gerado no envio.
- Funções `SECURITY DEFINER` resolvem somente o `organization_id` a partir do digest; sessão e contato são
  carregados sob RLS e revalidados a cada requisição (contato ativo com portal habilitado, cliente ativo).
- O contato vê apenas registros do próprio cliente, apenas versões enviadas (nunca rascunhos ou custos).

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

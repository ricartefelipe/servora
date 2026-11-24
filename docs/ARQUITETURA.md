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

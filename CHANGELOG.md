# Changelog

Todas as mudanças relevantes são registradas aqui. Formato baseado em
[Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e versionamento [SemVer](https://semver.org/lang/pt-BR/).

## [Não lançado]

## [1.5.0] - 2026-11-24

Busca rápida, auditoria legível, agenda ao vivo e gráficos no painel.

### Adicionado

- Busca rápida (Ctrl+K / Cmd+K, menu lateral e barra superior) em ordens de serviço, clientes, equipamentos e
  orçamentos, com cada grupo condicionado às mesmas permissões, escopos e módulos das listas, navegação por
  teclado e limite de requisições por membro.
- Gráficos no painel: ordens em aberto por situação e recebimentos dos últimos 7 dias no fuso da organização,
  com tabela de dados e descrição para leitores de tela.

### Alterado

- Auditoria com ações e alterações em português ("Campo: de → para"), nomes no lugar de identificadores e
  campos sensíveis sempre ocultos; leitura adaptada ao celular.
- Linha do horário atual na agenda atualizada em tempo real no fuso da organização e centralizada no celular.

### Segurança

- Termos de busca filtrados dos logs.
- Falso positivo de varredura de segredos registrado por impressão digital, sem reescrita de histórico.

## [1.4.0] - 2026-11-24

Interface interna redesenhada na direção "Precisão".

### Alterado

- Interface interna redesenhada na direção "Precisão": superfícies de porcelana quente com texto ameixa, menu
  lateral claro com marcador rubi no item ativo, fio rubi no topo, trilha de navegação na barra superior,
  títulos com faceta e tipografia Inter e JetBrains Mono servidas pela própria aplicação.
- Painel com capa rubi (saudação, visitas do dia, técnicos em campo e ordens em aberto), lista "Precisa de
  atenção" ordenada por gravidade com atalhos para as listas filtradas e próximas visitas; capa adaptada ao perfil.
- Marca e ícone passam a ser a gema facetada.
- Área do técnico com layout próprio para celular, cartão rubi da próxima visita e navegação inferior.
- Portal do cliente com cabeçalho, abas e acompanhamento do chamado por etapas.
- Listas, filtros, formulários e tabelas padronizados; tabelas viram cartões empilhados no celular.
- Papéis de cor: o rubi marca identidade, ação e "agora"; perigo usa rosa com ícone; valores em dinheiro sempre
  em tinta neutra; estados das ordens com um único mapa de tons em toda a aplicação.

### Corrigido

- Técnicos passam a ver no painel apenas as próprias visitas.
- Contraste AA em bordas de campos, registros arquivados, marcadores da agenda e rótulos do menu.

## [1.3.0] - 2026-11-24

Acesso pela raiz da aplicação e nova identidade visual.

### Alterado

- A raiz da aplicação (`/`) passa a abrir diretamente o formulário de acesso; quem já entrou é encaminhado às suas
  organizações. O endereço `/conta/entrar` redireciona para a raiz. A página pública de apresentação foi removida.
- Nova identidade visual: vermelho rubi como cor da marca, neutros grafite e dourado como destaque, aplicados à
  interface, aos e-mails, aos PDFs, ao ícone e ao manifesto do aplicativo.
- Telas de acesso, cadastro e recuperação com novo layout em duas colunas e painel ilustrado.
- Cores de status revisadas: estados neutros ou positivos não usam mais a cor da marca; botões de exclusão passam a
  ser contornados, distintos da ação principal.
- Ao sair do portal, o cliente vê uma página própria do portal em vez do formulário de acesso da equipe.
- Contraste revisado (WCAG AA) em textos auxiliares, marcadores, menu lateral e e-mails; caixas de seleção na cor
  da marca; indicadores em alerta destacados com ícone; página sem conexão com a identidade do produto.

## [1.2.0] - 2026-11-24

Relatórios gerenciais e correções de conclusão de ordens e de proteção de arquivos.

### Adicionado

- Relatórios gerenciais: ordens de serviço, produtividade por técnico, prazos (SLA), financeiro e consumo de
  materiais por período, com permissões de custo e financeiro, respeito aos módulos do plano e exportação CSV
  protegida contra injeção de fórmulas e auditada.

### Corrigido

- Concluir uma ordem com técnicos atribuídos falhava ao montar o relatório de execução (carregamento dos nomes dos
  técnicos).

- Dumps e backups de banco (`*.sql` na raiz, `*.backup`, `*.bak`) ignorados pelo Git e fora da imagem Docker;
  `db/structure.sql` continua versionado.

## [1.1.0] - 2026-11-24

Execução financeira completa no provedor de pagamentos e cobrança da própria plataforma.

### Adicionado

- Estornos executados no provedor de pagamento: envio após o commit, situação por estorno, verificação humana
  obrigatória quando a resposta é ambígua e sinalização dos estornos de pagamentos manuais.
- Nota fiscal de serviço (NFS-e) emitida pelo provedor de pagamentos: dados fiscais, emissão manual ou automática
  na quitação, acompanhamento da prefeitura, cancelamento e link da nota no portal do cliente.

## [1.0.0] - 2026-11-24

Ciclo completo da operação de serviços de campo: da solicitação à execução e ao resultado financeiro, com
integrações, operação e assinatura da plataforma.

### Adicionado

- Estoque: depósitos (central, técnico, veículo), entradas, transferências, ajustes auditados, estoque
  mínimo, saldos físico/reservado/disponível, histórico de movimentações e valor em estoque para perfis
  autorizados.
- Materiais na ordem de serviço: reservas, consumo com custo histórico, devoluções e liberação automática no
  cancelamento ou na conclusão.
- Proteções no banco: trigger que exige movimentação correspondente para alterar saldos, movimentações
  append-only e constraints contra saldo negativo e reserva acima do físico.
- Idempotência por chave de operação em entradas, transferências, ajustes e consumos.

- Financeiro operacional: contas a receber por ordem (parcelas), pagamentos parciais idempotentes,
  descontos e estornos com permissões próprias, cancelamento sem valor retido e histórico append-only.
- Despesas por ordem e margem prevista × realizada com custos históricos de material e mão de obra.
- Cobranças Pix e boleto por adapter: simulador determinístico e Asaas (sandbox), envio pela outbox fora de
  transações, consulta pela referência externa após respostas ambíguas, conciliação periódica e cancelamento
  remoto; chave de API criptografada por organização.

- Contratos de manutenção com condições versionadas, ativação, suspensão, retomada e encerramento,
  tipos de serviço cobertos, limite mensal de atendimentos e vínculo automático das ordens ao contrato vigente.
- Planos preventivos com periodicidade semanal, mensal ou anual (e múltiplos), âncora de calendário
  preservada, antecedência, modo "após a conclusão", reancoragem sem alterar ocorrências geradas, geração diária
  idempotente com recuperação gradual e identidade estável (plano, sequência).

- SLA: prazos de primeira resposta e resolução por prioridade, expediente semanal, feriados e fuso da
  organização, pausas por espera de aprovação, cliente ou peças, retomada na reabertura, alertas de risco e de
  estouro sem duplicidade, painel na ordem de serviço e indicador no painel inicial.

- Anexos da ordem de serviço (fotos e documentos) com validação do conteúdo pela assinatura do arquivo,
  limites de tamanho, download autorizado com cabeçalhos privados e Active Storage isolado por organização.
- PDFs da proposta comercial (versão enviada) e do relatório de execução (cada versão), gerados a partir dos
  dados congelados.
- Área do técnico (PWA): agenda dos próximos dias, tela de execução para celular, rascunhos e fila offline de
  checklist, registro técnico e apontamentos com sincronização idempotente, revalidação de acesso e detecção de
  conflitos; service worker restrito a assets estáticos.

- Portal do cliente ampliado: abertura de chamados (ordem em análise com notificação à equipe), acompanhamento
  das ordens e visitas, equipamentos com histórico, relatórios e propostas em PDF e cobranças com link de
  pagamento; navegação adaptada ao celular.
- API pública v1 com OpenAPI, credenciais com escopos, validade e revogação, paginação limitada, filtros e
  idempotência por `Idempotency-Key` na criação de ordens.
- Webhooks de saída assinados (HMAC-SHA256), com id de evento estável, retentativas, reenvio manual e proteção
  contra SSRF; webhooks de entrada do Asaas autenticados, gravados antes da confirmação e deduplicados.
- Tela de integrações com segredos exibidos uma única vez.

- Observabilidade: logs JSON por requisição, job e consulta lenta com id de correlação; métricas Prometheus
  protegidas por token (HTTP, jobs, outbox, filas, integrações, consultas lentas) sem rótulos de alta
  cardinalidade.
- Assinaturas da plataforma: planos com técnicos incluídos, técnicos adicionais, módulos adicionais (estoque,
  preventiva, financeiro, API), avaliação de 14 dias, taxa de implantação, vagas de técnico controladas e modo
  somente leitura após a avaliação sem ativação.

- Documentação de operação e produto: C4, modelo de dados, fluxos, políticas de calendário, dinheiro e custos,
  runbooks (com backup e restauração exercitados localmente) e roteiro de demonstração.

### Corrigido

- Plural em português nas telas (por exemplo, "5 dias" e "itens").
- CI com limite de tempo por job e no passo de instalação do cliente PostgreSQL (com retentativas de rede),
  para que falhas de rede do runner encerrem a execução em minutos.
- A aba selecionada é mantida após enviar formulários (o redirecionamento descartava o fragmento da URL).

## [0.1.0] - 2026-11-24

Primeira fatia vertical: organização, autenticação, permissões, clientes, equipamentos, orçamento com aprovação
pelo portal, ordem de serviço e agendamento.

### Adicionado

- Fundação do projeto: Rails 8.1, PostgreSQL 18 com papéis owner/aplicação, Solid Queue/Cache/Cable em
  bancos separados, Docker multi-stage, Docker Compose, CI com análise de segurança, cobertura e validação
  de migrations.
- Probes de liveness (`/up`) e readiness (`/ready`).
- Documentação inicial: requisitos, decisões, arquitetura, status e guia de contribuição.
- Identidade com Devise: cadastro, confirmação por POST, bloqueio por tentativas, recuperação de senha,
  sessões revogáveis no servidor e verificação em duas etapas (TOTP e códigos de recuperação).
- Organizações multitenant com RLS, FKs compostas e contexto transacional; onboarding, seleção e troca.
- Equipe: sete papéis com matriz de permissões, convites de uso único, desativação imediata e auditoria.
- Transactional Outbox com despachante recorrente, lease, retentativas com backoff, histórico de falhas e
  reprocessamento autorizado; convites e notificações passam a ser entregues pela outbox.
- Notificações internas em tempo real por stream privado de cada vínculo.
- Clientes PF/PJ com locais de atendimento e contatos; equipamentos com histórico de localização, proprietário e
  estado operacional, arquivamento e garantia informada.
- Catálogo de serviços e peças com custo restrito; orçamentos numerados e versionados com snapshot imutável,
  digest do conteúdo, descontos, validade, histórico de negociação e cancelamento.
- Portal do cliente com link de uso único, sessão restrita e aprovação ou recusa da versão vigente com evidências;
  registro interno de decisões comunicadas por outros canais.
- Ordens de serviço com máquina de estados, conversão idempotente de orçamentos aprovados, tipos de serviço com
  checklist obrigatório, registro técnico, itens adicionais com autorização, conclusão com relatório versionado,
  cancelamento e reabertura auditados; escopo restrito para técnicos.
- Agenda diária e semanal, técnicos com competências e horários, equipes, ausências, deslocamento configurável,
  agendamento atômico de equipes protegido por exclusion constraint, reagendamento, cancelamento, ausência do
  cliente, sugestão determinística de técnicos e apontamentos com custo histórico de mão de obra.

[Não lançado]: https://github.com/ricartefelipe/servora/compare/v1.5.0...develop
[1.5.0]: https://github.com/ricartefelipe/servora/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/ricartefelipe/servora/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/ricartefelipe/servora/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/ricartefelipe/servora/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/ricartefelipe/servora/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ricartefelipe/servora/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/ricartefelipe/servora/releases/tag/v0.1.0

# Requisitos e critérios de aceite

Este documento descreve o que o Servora precisa fazer e como cada requisito é verificado.
O estado de implementação de cada item é acompanhado em [`STATUS.md`](STATUS.md).

Convenções: **RF** = requisito funcional, **RNF** = requisito não funcional. Cada critério de
aceite (CA) é verificável por teste automatizado ou por inspeção documentada.

## 1. Produto

O Servora é uma plataforma SaaS B2B multitenant para empresas de serviços de campo e
manutenção (climatização, manutenção predial, assistência técnica e equipamentos
comerciais). Acompanha a operação desde a solicitação do cliente até a execução e o resultado
financeiro, com histórico e rastreabilidade.

Dois relacionamentos comerciais são distintos e nunca compartilham tabelas:

| Relacionamento | Partes | Onde vive |
|---|---|---|
| Assinatura da plataforma | Servora ↔ empresa contratante | `plans`, `plan_modules`, `subscriptions` |
| Contrato de manutenção | Empresa contratante ↔ seus clientes | `maintenance_contracts` e versões |

## 2. Organizações, membros e permissões

- **RF-ORG-01** Cadastro de organização com onboarding guiado (dados da empresa, fuso horário,
  horário de atendimento, primeiro convite).
  - CA: o usuário que cria a organização torna-se proprietário e passa a operar dentro dela.
- **RF-ORG-02** Convites por e-mail com validade, revogação e uso único.
  - CA: convite expirado, revogado ou já aceito é recusado; o token é armazenado apenas como digest.
- **RF-ORG-03** Um usuário pode participar de várias organizações com papéis diferentes e alternar entre elas.
  - CA: a troca de organização valida o vínculo ativo no servidor; dados locais do dispositivo são limpos.
- **RF-ORG-04** Desativação de acesso de membro com efeito imediato.
  - CA: a próxima requisição do membro desativado é negada, inclusive em sessões já abertas.
- **RF-ORG-05** Papéis iniciais: proprietário, administrador, coordenador operacional, atendente,
  técnico, financeiro e auditor, com matriz de permissões documentada em `ARQUITETURA.md`.
  - CA: specs de policy cobrem cada permissão sensível (custos, margens, aprovação, estoque, financeiro).
- **RF-ORG-06** Técnicos acessam apenas atendimentos atribuídos a eles e dados permitidos pela política.
- **RF-ORG-07** Custos internos e margens são visíveis apenas a papéis com permissão explícita.

## 3. Clientes, locais e equipamentos

- **RF-CLI-01** Clientes pessoa física e jurídica com validação de CPF/CNPJ.
- **RF-CLI-02** Contatos, endereços e múltiplos locais de atendimento por cliente.
- **RF-CLI-03** Pessoas autorizadas a acompanhar e/ou aprovar serviços.
- **RF-CLI-04** Histórico de atendimento por cliente, local e equipamento.
- **RF-EQP-01** Equipamento com tipo, fabricante, modelo, número de série, patrimônio, local,
  data de instalação, garantia informada, estado operacional, anexos e observações.
- **RF-EQP-02** Mudanças de local e de proprietário preservam histórico (eventos imutáveis).
- **RF-EQP-03** Equipamentos com ordens de serviço não podem ser excluídos; apenas arquivados.
  - CA: a exclusão é bloqueada por regra e por chave estrangeira.

## 4. Catálogo e orçamentos

- **RF-CAT-01** Catálogo de serviços e peças com unidade, duração estimada, preço de venda e custo
  (custo visível apenas com permissão).
- **RF-ORC-01** Orçamento com serviços e materiais, quantidades, unidades, descontos, condições de
  pagamento, validade, observações e versões.
- **RF-ORC-02** Itens enviados ou aprovados são snapshots: mudanças no catálogo não os alteram.
  - CA: spec altera preço do catálogo após envio e verifica que a versão enviada mantém o valor.
- **RF-ORC-03** Mudança relevante após aprovação exige nova versão com nova autorização.
- **RF-ORC-04** Aprovação ou rejeição pelo cliente registra versão, responsável, data e evidências
  (IP, agente, digest do conteúdo apresentado). Não é apresentada como assinatura certificada.
  - CA: aprovar uma versão substituída é recusado.
- **RF-ORC-05** Conversão de orçamento aprovado em ordem de serviço é idempotente, inclusive sob
  requisições simultâneas.
  - CA: duas conexões convertendo ao mesmo tempo resultam em exatamente uma ordem.

## 5. Ordens de serviço

- **RF-OS-01** Ordem com cliente, local, equipamentos, origem, prioridade, descrição, serviços
  autorizados, técnicos/equipe, visitas, checklists, apontamentos, materiais, evidências,
  diagnóstico, solução, histórico de transições e relatório final.
- **RF-OS-02** Máquinas de estados separadas para ordem e visita; transições inválidas são rejeitadas.
- **RF-OS-03** Concluir uma visita não conclui a ordem.
- **RF-OS-04** Estados de espera por peças e por cliente; cancelamento; reabertura autorizada que
  preserva relatório e execução anteriores.
- **RF-OS-05** Conclusão exige os itens obrigatórios do checklist do tipo de serviço.
  - CA: concluir com item obrigatório pendente é recusado com mensagem explicativa.
- **RF-OS-06** Serviços adicionais exigem autorização antes de gerar cobrança.

## 6. Agenda, despacho e SLA

- **RF-AGD-01** Agenda diária e semanal por técnico e equipe, com horários de trabalho, ausências,
  duração prevista, intervalo de deslocamento configurável e competências.
- **RF-AGD-02** Reagendamento, cancelamento e identificação de conflitos.
- **RF-AGD-03** Reservas incompatíveis do mesmo técnico são impedidas pelo PostgreSQL
  (exclusion constraint sobre `tstzrange` semiaberto), mesmo com usuários simultâneos.
  - CA: spec concorrente com duas conexões resulta em uma reserva e um conflito.
- **RF-AGD-04** Visita de equipe reserva todos os integrantes atomicamente.
  - CA: conflito em um integrante não deixa reservas parciais.
- **RF-AGD-05** Sugestão determinística de técnicos disponíveis por competência e agenda (não é
  otimização de rotas).
- **RF-SLA-01** Prazos de primeira resposta e resolução por prioridade, calendário de trabalho,
  feriados e fuso da organização.
- **RF-SLA-02** Eventos que iniciam, pausam (espera por cliente/peças) e encerram a contagem.
- **RF-SLA-03** Alertas de vencimento sem duplicidade.

## 7. Contratos e manutenção preventiva

- **RF-CTR-01** Contratos com vigência, escopo, serviços cobertos, limites de atendimento,
  condições comerciais, versões, suspensão e encerramento.
- **RF-PRV-01** Planos preventivos com periodicidade configurável (semanal, mensal, anual e múltiplos).
- **RF-PRV-02** Âncora de calendário preservada (dia 31 → último dia do mês; 29/02 → 28/02 em anos não bissextos).
- **RF-PRV-03** Recuperação após indisponibilidade do agendador sem duplicidade; identidade estável
  da ocorrência (plano + número sequencial).
- **RF-PRV-04** Alterar o plano não recria ocorrências já geradas nem reescreve ordens executadas.
- **RF-PRV-05** Modo "após conclusão" calcula a próxima data a partir da conclusão efetiva.
- **RF-PRV-06** Contrato suspenso não gera ocorrências; ao retomar, datas que caíram na suspensão não são
  geradas. O término do contrato limita as datas e desativa os planos.

## 8. Estoque

- **RF-EST-01** Depósitos (central, técnico, veículo); peças com unidade de medida.
- **RF-EST-02** Entrada, reserva para ordem, consumo, devolução, transferência, ajuste autorizado,
  estoque mínimo e histórico de movimentações.
- **RF-EST-03** Saldos físico, reservado e disponível; saldo só muda com movimento correspondente
  (garantido por trigger no banco).
- **RF-EST-04** Proteção contra saldo negativo, reserva acima do disponível, consumo duplicado,
  devolução acima do consumido, transferência parcial e disputa pela última unidade.
  - CA: spec concorrente com duas ordens reservando a última unidade resulta em uma reserva.
- **RF-EST-05** Custo médio móvel com 4 casas decimais (arredondamento comercial, metade para cima, igual ao
  `round` do PostgreSQL); quantidades com 3 casas e valores com 2. O custo aplicado ao consumo fica registrado
  e não muda com compras posteriores; devoluções voltam ao custo do consumo original.
- **RF-EST-06** Cancelamento e conclusão da ordem liberam reservas não consumidas (via outbox).
- **RF-EST-07** Técnicos veem apenas os depósitos sob sua responsabilidade e registram consumo nas ordens em
  que atuam; ajustes e estoque mínimo exigem permissão própria; custos só com `costs_view`.

## 9. Financeiro operacional

- **RF-FIN-01** Contas a receber por ordem, pagamentos parciais, descontos autorizados, cancelamentos,
  estornos e histórico financeiro imutável.
- **RF-FIN-02** Custos de materiais (histórico), mão de obra por apontamento (custo/hora vigente no
  apontamento) e despesas adicionais.
- **RF-FIN-03** Margem prevista e realizada por ordem; faturamento, recebimento e resultado operacional
  são apresentados separadamente.
- **RF-FIN-04** Dinheiro em BRL com `decimal(14,2)`; quantidades `decimal(14,3)`; custos unitários
  `decimal(14,4)`. Nunca `Float`.
- **RF-FIN-05** Adaptador de pagamentos: simulador determinístico e Asaas (sandbox), com criação de
  cobrança, consulta, confirmação, falha e cancelamento. Estornos são registrados no Servora (histórico,
  saldo e auditoria); a devolução no meio de pagamento é uma etapa operacional fora do sistema nesta versão.
- **RF-FIN-06** Resposta perdida do provedor é resolvida por consulta pela referência externa; a
  cobrança não é repetida cegamente.
- **RF-FIN-07** Fatura comercial não é apresentada como nota fiscal. Dados de cartão nunca são armazenados.
- **RF-FIN-08** Chamadas ao provedor nunca ocorrem dentro de transações; o envio é disparado pela outbox
  após o commit e uma conciliação periódica cobre confirmações perdidas.

## 10. Campo e funcionamento offline

- **RF-CAM-01** PWA responsiva e instalável para o técnico: agenda, dados autorizados, início e término,
  checklist, diagnóstico, fotos, materiais, relatório e solicitação de conclusão.
- **RF-CAM-02** Offline limitado a rascunhos de apontamentos, diagnóstico e checklist.
- **RF-CAM-03** Sincronização com identificador de operação, idempotência, versão, detecção de conflito,
  feedback de pendência/erro e revalidação de permissões no servidor.
- **RF-CAM-04** Dados locais separados por usuário e organização e limpos no logout e na troca de contexto;
  o service worker não armazena respostas autenticadas.

## 11. Anexos e relatórios

- **RF-ANX-01** Limite de tamanho, allowlist de formatos e validação do conteúdo real (assinatura do arquivo).
- **RF-ANX-02** Anexos associados ao tenant e ao registro autorizado; downloads sempre autenticados.
  - CA: download de anexo de outra organização retorna 404; rotas padrão do Active Storage não existem.
- **RF-ANX-03** Retenção e exclusão controladas.
- **RF-REL-01** PDFs de orçamento e de execução gerados a partir dos dados reais, preservando versão e snapshot.

## 12. Portal do cliente e integrações

- **RF-POR-01** Portal com sessão restrita obtida por link temporário (finalidade, expiração, revogação),
  trocado por sessão via POST.
- **RF-POR-02** Abrir solicitação, consultar equipamentos, histórico, agendamentos, aprovar/rejeitar
  orçamento, acompanhar ordens, baixar relatórios e consultar cobranças — sem custos ou margens.
- **RF-API-01** API versionada (`/api/v1`) com OpenAPI, paginação limitada, filtros permitidos e
  credenciais revogáveis com escopos.
- **RF-WHK-01** Webhooks recebidos: autenticação conforme o provedor, persistência antes da confirmação,
  deduplicação e processamento assíncrono.
- **RF-WHK-02** Webhooks enviados: assinatura HMAC, identificador estável, retentativas e proteção contra SSRF.

## 13. Jobs e consistência

- **RF-OUT-01** Transactional Outbox: evento gravado na mesma transação do negócio.
- **RF-OUT-02** Reivindicação com lease (`FOR UPDATE SKIP LOCKED`), deduplicação, retentativas limitadas,
  recuperação após reinício, histórico de falhas e reprocessamento autorizado.
  - CA: specs cobrem falha após commit e antes do enqueue, execução repetida e reinício durante o processamento.
- **RF-OUT-03** Jobs carregam apenas identificadores e reconstituem o contexto autorizado.

## 14. Segurança e auditoria

- **RNF-SEG-01** Devise com confirmação de e-mail, recuperação de senha, bloqueio por tentativas,
  sessões revogáveis e logout seguro.
- **RNF-SEG-02** MFA (TOTP) obrigatório para perfis privilegiados (proprietário, administrador e financeiro).
- **RNF-SEG-03** Cookies HttpOnly, Secure em produção, SameSite=Lax; CSRF; CSP restritiva; rate limiting.
- **RNF-SEG-04** Defesa em profundidade multitenant: escopo explícito, Pundit, FKs compostas por
  organização, RLS e papel de aplicação sem privilégios de bypass.
- **RNF-SEG-05** Auditoria com ator, organização, ação, recurso, horário e alterações relevantes,
  com redação de dados sensíveis.
- **RNF-SEG-06** Os controles existentes não constituem declaração de conformidade jurídica ou regulatória.

## 15. Qualidade, testes e operação

- **RNF-QLD-01** Suíte de regras puras executa sem Rails, banco, navegador ou rede (`bin/rspec-unit`).
- **RNF-QLD-02** Specs com Active Record usam PostgreSQL com o papel de aplicação.
- **RNF-QLD-03** Cobertura do núcleo (domínio, casos de uso, consultas, formulários, policies):
  ≥ 90% de linhas e ≥ 80% de branches (`bin/coverage-check`).
- **RNF-QLD-04** Testes concorrentes usam conexões separadas e sincronização determinística (sem `sleep`).
- **RNF-QLD-05** Ordem aleatória com seed registrada.
- **RNF-OPS-01** Logs estruturados com correlação entre requisição, ordem, integração e job.
- **RNF-OPS-02** Métricas de latência, erros, queries lentas, fila, idade da outbox, retries, falhas
  permanentes, conflitos de agenda e integrações, sem labels de alta cardinalidade.
- **RNF-OPS-03** Liveness (`/up`) sem dependências; readiness (`/ready`) verifica bancos e migrations.
- **RNF-OPS-04** CI com RuboCop, Brakeman, Bundler Audit, verificação de segredos, testes, cobertura,
  system specs, build de assets, validação de migrations, reconstrução por `structure.sql`,
  build e análise da imagem.

# Roteiro de demonstração

Ambiente: `cp .env.example .env && docker compose up --build` (o serviço `migrate` executa
`bin/db-prepare --seed`). Aplicação em `http://localhost:3000`, e-mails no Mailpit em `http://localhost:58025`.
Senha das contas de demonstração: valor de `SEED_PASSWORD` (padrão local `servora-demo-2026`).

| Pessoa | E-mail | Perfil |
|---|---|---|
| Ana Ribeiro | `ana@clima-norte.test` | Proprietária — Clima Norte (organização A) |
| Bruno Costa | `bruno@clima-norte.test` | Coordenador |
| Carla Mendes | `carla@clima-norte.test` | Atendente |
| Diego Alves | `diego@clima-norte.test` | Técnico (Equipe Refrigeração, van própria) |
| Eduarda Lima | `eduarda@clima-norte.test` | Técnica (Equipe Refrigeração) |
| Fábio Souza | `fabio@clima-norte.test` | Técnico (elétrica) |
| Gabriela Rocha | `gabriela@clima-norte.test` | Financeiro |
| Heitor Nunes | `heitor@clima-norte.test` | Auditor (consulta, custos e trilha de auditoria, sem alterar nada) |
| Igor Martins | `igor@predial-sul.test` | Proprietário — Predial Sul (organização B) |
| Júlia Freitas | `julia@predial-sul.test` | Técnica — Predial Sul |

Ao entrar na organização, cada pessoa chega à página do seu perfil: os técnicos vão direto para a área de campo
(**Minha agenda**, em `/campo`, pensada para o celular); o auditor, para a **trilha de auditoria** (`/auditoria`);
os demais perfis, para o painel. O auditor vê as telas de consulta, os custos e a auditoria, sem permissão para
alterar dados.

Perfis com verificação em duas etapas obrigatória (proprietário, administrador, financeiro) têm prazo de
carência para ativá-la; a demonstração pode seguir dentro do prazo. No modo de demonstração (`SERVORA_DEMO=1`) a
tela de acesso lista as contas de Ana, Bruno, Carla, Diego, Gabriela e Heitor com a senha, e essa exigência não se
aplica.

A organização A já abre com cerca de seis semanas de movimento e a agenda de hoje; o que vem carregado está
descrito em [Dados pré-carregados](#dados-pré-carregados).

1. **Entrar na organização A** — em `http://localhost:3000` (a raiz abre o formulário de acesso), entrar como Bruno;
   a organização Clima Norte é aberta pelo seletor.
2. **Cliente, local e equipamento** — Clientes → Novo cliente (com CNPJ válido e primeiro local) → no cliente,
   Novo local pelo modal → Equipamento com número de série.
3. **Orçamento aprovado pelo portal** — Orçamentos → Novo (cliente e local) → incluir itens do catálogo → Enviar
   ao cliente (os contatos aprovadores recebem o link por e-mail; o botão "Enviar para…" reenvia) → abrir o
   e-mail no Mailpit → Continuar → Aprovar. O orçamento mostra a aprovação com contato, canal e data; o conteúdo
   da versão fica congelado.
4. **Gerar a ordem** — no orçamento aprovado, Gerar ordem de serviço. O botão passa a "Ver ordem de serviço" e
   repetir a ação leva à mesma ordem (conversão idempotente, também sob requisições simultâneas).
5. **Agendar a equipe** — na ordem, Agendar visita → equipe "Equipe Refrigeração" (reserva atômica de todos os
   integrantes) → a agenda diária mostra a visita.
6. **Conflito recusado** — agendar outra visita para Diego no mesmo horário: a interface explica o conflito; o
   banco recusa a reserva (exclusion constraint).
7. **Reservar peças** — aba Materiais → reservar "Capacitor 35+5 µF" do Almoxarifado central; o saldo mostra
   físico, reservado e disponível.
8. **Checklist e execução** — entrar como Diego → Minha agenda → abrir a ordem → iniciar visita, responder o
   checklist, registrar diagnóstico e solução, apontar horas. (Opcional: desligar a rede no navegador, salvar,
   religar e ver a sincronização.)
9. **Consumir material e concluir** — como Bruno, aba Materiais → consumir a reserva → Concluir a ordem. As
   reservas não consumidas são liberadas automaticamente.
10. **Relatório e cobrança simulada** — aba Relatórios → baixar o PDF da versão 1. Como Gabriela, no painel
    Financeiro da ordem → Faturar → na conta, Gerar cobrança (Pix) com o provedor Simulador.
11. **Pagamento e margem** — Simular pagamento → a conta fica Quitada; no painel da ordem, margem prevista ×
    realizada com material ao custo do consumo, mão de obra e despesas.
12. **Repetição sem duplicidade** — em uma conta em aberto, Registrar pagamento e reenviar o mesmo formulário
    (voltar no navegador e enviar de novo): um único pagamento é registrado, porque o formulário carrega uma
    chave de operação. O mesmo vale para entradas de estoque e para operações do técnico enviadas offline.
13. **Ocorrência preventiva** — Contratos → "Manutenção preventiva — Loja Paulista" → plano "Splits da Loja
    Paulista" → Gerar ocorrências devidas → a ordem preventiva nº 1 aparece vinculada ao contrato e coberta por ele.
    Gerar de novo não cria outra.
14. **Isolamento da organização B** — sair e entrar como Igor (Predial Sul): clientes, ordens, estoque e contas
    da Clima Norte não aparecem; acessar diretamente a URL de uma ordem da organização A retorna "não
    encontrado" (RLS no banco, além das policies).

## Dados pré-carregados

Além dos cadastros (clientes, catálogo, técnicos, estoque, contrato e SLA), `db/seeds/10_demo_activity.rb`
registra o histórico pelos próprios casos de uso — com transições, auditoria, eventos, notificações, razão de
estoque, lançamentos financeiros e prazos de SLA coerentes. Vem ativada em desenvolvimento e é controlada por
`SEED_DEMO_ACTIVITY` (`1` liga, `0` desliga; a demonstração pública usa `1`).

As datas são relativas ao instante da carga, no fuso da organização, e **só fica registrado o que já aconteceu
nesse instante**: uma carga às 03:55 mostra todas as visitas de hoje como agendadas; uma carga às 15:00 mostra as
da manhã realizadas e uma em atendimento. No modo de demonstração o restante do dia acontece sozinho, nos horários
previstos (veja [O que muda ao longo do dia](#o-que-muda-ao-longo-do-dia)). Notificações, links do portal e alertas
de prazo levam o horário em que teriam ocorrido (o prazo em risco é avisado antes do estouro). Os cadastros de base
(pessoas, equipamentos, estoque inicial, contrato) ficam datados do início da história, então o razão de estoque lê
em ordem cronológica. Vencimentos e recebimentos caem sempre em dias úteis. A carga é idempotente (não duplica ao
rodar de novo).

Na Clima Norte, ao entrar:

- **Clientes** — os da história (Horizonte Supermercados, Renato Albuquerque, Clínica Vida Plena, Restaurante
  Sabor da Serra, Academia Movimento e Prisma Contabilidade) e mais 20 clientes do dia a dia: residências da zona
  norte de São Paulo e de Guarulhos (uma a três unidades) e pequenas empresas da região e do ABC — padaria,
  drogaria, clínica odontológica, escola de idiomas, escola infantil, pet shop, mercadinho, salão, escritório de
  advocacia, coworking, laboratório e oficina (duas a quatro unidades). São 26 clientes e cerca de 70
  equipamentos de marcas e modelos reais (LG Dual Inverter, Samsung WindFree, Daikin, Fujitsu, Springer Midea,
  Carrier, Gree, Elgin, Consul, câmaras frias Frigotech), com números de série e garantias variadas — os clientes
  da história também: o Renato tem um split piso-teto Carrier na sala (garantia vencida) e um split Daikin no
  quarto.
- **Histórico** — em cada dia útil das seis semanas anteriores (até ontem), de três a cinco visitas de rotina,
  espalhadas entre manhã e tarde e entre os três técnicos (nos últimos dias, mais as visitas da história, até seis
  ou sete no dia; em média cerca de quatro por dia útil). Cada técnico aponta em campo de 20% a 30% do expediente:
  é menos do que uma equipe real ocuparia, de propósito — a agenda fica legível, e sobra horário livre para o
  visitante agendar as próprias visitas. Em cada uma: chamado,
  visita agendada, checklist respondido, diagnóstico e solução, materiais consumidos, itens autorizados pelo
  cliente, horas apontadas, relatório de execução, cobrança e recebimento (Pix na hora, transferência alguns dias
  úteis depois ou boleto no vencimento — os boletos que ainda não venceram seguem em aberto). Os chamados saem do
  tipo de cada equipamento (capacitor, dreno, vazamento, higienização, sensor de temperatura, disjuntor, contator,
  bomba de dreno, isolamento, motor do ventilador; nas câmaras frias, gelo e filtro secador), cada um com duas ou
  três redações de sintoma, diagnóstico e solução, e as peças trocadas saem do estoque (o sensor NTC 10 kΩ
  inclusive); as residências têm os reparos mais simples e tíquetes menores, as empresas também os maiores. As
  visitas de avaliação para instalação ou remanejamento registram só as medições: o único orçamento que segue uma
  delas é o remanejamento da Patrícia (abaixo). As preventivas seguem o intervalo de cada equipamento
  (mensal, trimestral ou semestral, como no PMOC das empresas) e aparecem com a origem "Manutenção preventiva". O
  histórico de cada equipamento é coerente: nenhum recebe dois corretivos em menos de três semanas nem duas
  preventivas no mesmo período; uma residência tem no máximo um pedido por equipamento mais um (três no total),
  com duas semanas entre eles; em qualquer período de 30 dias uma empresa abre no máximo um chamado a mais que o
  número de equipamentos (dois a mais quando o pedido preenche um dia de pouco movimento da equipe; preventivas e
  orçamentos aprovados não contam); nenhum cliente abre dois pedidos com minutos de diferença. Fábio atende os chamados elétricos; Diego e Eduarda, a
  refrigeração. Os materiais usados são repostos toda semana (entrada "Reposição semanal — NF …"), então os saldos
  ficam perto do estoque inicial. Prioridade e atraso são independentes: cerca de um corretivo em seis é de
  prioridade alta (preventivas nunca); cerca de um em quatro desses foi encerrado pelo escritório só no dia
  seguinte, e alguns normais esperaram vaga ou foram respondidos tarde. O relatório de SLA mostra na resolução
  cerca de 75% a 85% dos prazos de prioridade alta e 93% a 97% dos de prioridade normal cumpridos, e no total
  cerca de 94%.
- **Orçamentos** — um rascunho (troca de placa eletrônica, Renato); um enviado na **versão 2** aguardando a
  aprovação de Paula (higienização da Loja Paulista: a versão 1 foi enviada anteontem e, a pedido dela, a versão 2
  inclui a evaporadora do depósito e a bomba de dreno — o motivo está nas observações; o link está no Mailpit e no
  portal dela); um **aprovado pela Academia no portal** ontem à noite e ainda não convertido em ordem (motor
  ventilador e contator do split da sala de spinning — serve ao passo 4 do roteiro); um aprovado pela Clínica e
  convertido em ordem; um recusado pela Academia (com o motivo) e um vencido sem resposta (Prisma). Do dia a dia,
  instalações, higienizações e trocas aprovadas e executadas pela equipe (a instalação registra o equipamento
  novo), três recusados com o motivo (mercadinho, residência e salão), um vencido e o remanejamento do split do
  quarto da Patrícia, enviado no dia seguinte à visita de avaliação de Eduarda e aguardando resposta — de 15 a 20
  orçamentos ao todo.
- **Ordens em aberto** — um **pedido aberto pelo portal** por Renato ontem depois das 17:00 ("Split do quarto
  parado — residência", prioridade alta, vinculado ao split Daikin do quarto, que aparece como "Parado"),
  aguardando triagem (ainda sem tipo de serviço): o prazo de primeira resposta não estava estourado na carga e
  estoura no meio da manhã se ninguém agendar a visita; uma ordem aprovada sem visita
  (avaliação para instalação de split no depósito da Horizonte); uma aguardando peças (câmara fria do CD: dois relés
  de partida 220 V autorizados, um reservado no almoxarifado e o outro encomendado, com o prazo pausado bem antes
  do vencimento); a preventiva geral da Academia, com itens aprovados, que entra em execução à tarde; as visitas de
  hoje e do próximo dia útil; e a preventiva nº 1 do contrato do restaurante ("Câmara fria da Matriz — preventiva
  nº 1"), gerada pela rotina diária. Os equipamentos ficam em atenção enquanto há ordem aberta para eles e voltam a
  operar quando ela é concluída.
- **Agenda de hoje** — Diego às 08:00 (restaurante), às 11:00 (pedido do portal do Renato, agendado depois da
  triagem) e às 13:30 (preventiva da Academia); Eduarda às 08:00 (Clínica);
  Fábio às 10:00 (Prisma); Eduarda e Fábio juntos às 15:30 (cassete da Loja Paulista). No próximo dia útil, Diego
  às 08:30 (revisão do consultório 1 da Clínica, cancelada às 16:25) e às 14:00 (pedido da escola que chega às
  14:10), Fábio às 09:00 e às 14:00 e Eduarda às 13:30 (e às 10:30, o retorno à câmara fria do CD, agendado no fim
  do dia).
  Em fim de semana ou feriado a agenda de hoje é um plantão, e os recebimentos previstos para hoje ficam para o
  próximo dia útil.
- **Financeiro** — "Recebido no mês" e o gráfico "Recebido · últimos 7 dias" com os recebimentos do período (no
  primeiro dia do mês, "Recebido no mês" começa zerado), boletos e parcelas em aberto e uma conta vencida
  parcialmente paga (Renato).
- **Precisa de atenção** — OS com prazo em risco (revisão do consultório 1), conta vencida, equipamentos em
  atenção ou parados e itens abaixo do mínimo no almoxarifado: filtro secador e relé de partida (disponível zero, mínimo
  dois).
- **Contratos** — o da Horizonte ("Manutenção preventiva — Loja Paulista") cobre preventiva e corretiva da loja e
  do centro de distribuição, sem limite mensal; o do restaurante ("Manutenção da câmara fria — Matriz") cobre
  preventiva e até oito corretivas por mês e já tem a primeira ocorrência gerada. Todas as ordens desses clientes
  aparecem cobertas, com **uma exceção proposital**: a avaliação para instalação de split no depósito da Horizonte
  é do tipo "Instalação de equipamento", que o contrato não cobre — a ordem mostra "Tipo de serviço não coberto
  pelo contrato." e deve ser orçada à parte.

A Predial Sul tem duas ordens próprias (a inspeção mensal dos elevadores, de prioridade baixa, agendada para o
próximo dia útil dentro do prazo, e o nivelamento do elevador social, agendado para hoje às 09:00 com Júlia) e
uma entrada de estoque, para que o isolamento entre organizações seja visto com dados dos dois lados.

O roteiro acima continua válido sobre esses dados: ao agendar (passo 5), escolha um horário livre — por exemplo,
no segundo dia útil a partir de hoje, ainda sem visitas; para ver o conflito (passo 6), basta tentar Fábio às 09:00 do
próximo dia útil, horário de uma visita já agendada; no passo 4, o orçamento aprovado da Academia já pode gerar a ordem; no
passo 8, Diego pode iniciar uma visita de hoje que ainda esteja agendada; a conta em aberto do passo 12 pode ser a
parcela 2/2 da Clínica; e o plano do passo 13 ("Splits da Loja Paulista") continua sem ocorrências geradas.

## O que muda ao longo do dia

No modo de demonstração (`SERVORA_DEMO=1`, com `SEED_DEMO_ACTIVITY=1` no `worker`), a tarefa recorrente
`Demo::AdvanceStoryJob` aplica a cada 5 minutos os eventos de hoje cujo horário já passou, com a data e a hora de
cada um (o dia nunca é antecipado). Quem entra às 08:00, às 11:00 ou às 16:00 encontra a empresa em pontos
diferentes do mesmo dia (horários de Brasília; na Clima Norte, salvo indicação):

| Horário | O que acontece |
|---|---|
| 07:30 | Diego (restaurante) e Eduarda (Clínica) saem para as primeiras visitas: "Em deslocamento". |
| 08:00 | As duas visitas começam; as ordens passam a "Em andamento". Na Predial Sul, Júlia sai às 08:30 e começa o nivelamento às 09:05. |
| 09:00–09:30 | Diagnóstico, materiais (capacitor da van do Diego, que fica abaixo do mínimo) e itens autorizados; as duas visitas terminam. Fábio sai para a Prisma às 09:30. |
| ~09:20–09:50 | Sem triagem, o pedido do portal do Renato entra em alerta e estoura o prazo de primeira resposta ("Precisa de atenção"): é o único prazo perdido do dia e fica no relatório de SLA. |
| 09:40–09:55 | Ordens do restaurante e da Clínica concluídas e faturadas; **Pix do restaurante recebido** às 09:50. |
| 10:05–11:50 | Fábio em atendimento na Prisma (troca do contator e do disjuntor); conclusão e cobrança. Na Predial Sul, o nivelamento termina às 10:40 e a ordem é concluída às 11:00. |
| 10:15–10:35 | Bruno faz a triagem do pedido do Renato — classifica como "Atendimento corretivo", o que traz o checklist — e agenda Diego para as 11:00; Diego sai às 10:35 (o alerta de primeira resposta deixa o painel). |
| 11:05–12:15 | Diego atende o split do quarto do Renato (placa travada após a queda de energia), responde o checklist às 11:35 e conclui às 11:50, bem dentro do prazo de resolução; o split volta a "Operando" e a ordem é faturada. |
| 11:10–11:15 | **Chega o segundo relé de partida** (NF de compra): o relé deixa a lista de abaixo do mínimo e a peça é reservada para a câmara fria do CD. |
| 13:00–13:40 | Diego sai e começa a preventiva geral da Academia (primeira leitura do checklist às 13:55). |
| 14:10–14:30 | **Chega um pedido novo**: a escola Pequeno Saber avisa por mensagem que o split da sala do maternal está pingando; Carla registra a ordem e Bruno agenda Diego para o próximo dia útil às 14:00. |
| 14:20 | **Renato quita a conta vencida** e a do atendimento da manhã por Pix: a conta sai de "Precisa de atenção". |
| 14:40 | A avaliação para instalação no depósito da Horizonte é agendada (Fábio, próximo dia útil). |
| 15:05–15:40 | Eduarda e Fábio saem e começam o atendimento do cassete da Loja Paulista. |
| 16:10–16:55 | Diego conclui a preventiva da Academia (filtros, dreno e gás da reserva); ordem concluída e faturada. |
| 16:20–16:25 | A Clínica pede para aguardar o fim da reforma da recepção: a revisão do consultório 1, em risco desde a manhã, passa a "Aguardando cliente" com o prazo pausado, e Bruno cancela, com o motivo, a visita do próximo dia útil (ela será reagendada quando a clínica avisar). |
| 16:50–17:45 | Cassete da Loja Paulista concluído e faturado: o dia termina com todas as visitas realizadas. |
| 17:40 | Bruno agenda o retorno à câmara fria do CD para o próximo dia útil; a ordem sai de "Aguardando peças". Depois disso o painel não mostra nenhuma OS com prazo estourado nem em risco. |

Também entram no dia os boletos e transferências do histórico que vencem hoje. O visitante pode agir antes da
história: se ele iniciar, concluir ou cancelar uma visita, concluir ou faturar uma ordem ou registrar o pagamento de
uma conta, a história respeita o que foi feito e deixa de lado os passos seguintes daquela ordem. Os pedidos que o
visitante cria não são tocados. Entre a meia-noite e a recarga das 03:55 nada muda.

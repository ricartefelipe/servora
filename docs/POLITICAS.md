# Políticas de calendário, dinheiro e custos

## Datas e fusos

- Instantes são gravados em `timestamptz`; telas e documentos usam o fuso da organização.
- Agenda: intervalos semiabertos `[início, término + deslocamento)`; horários de trabalho no fuso da organização.
- SLA: expediente semanal (até dois intervalos por dia), feriados e fuso da organização; limites dos intervalos
  montados com o relógio local; tempo medido em segundos. Políticas podem contar continuamente (24×7).
- Preventiva: datas sempre calculadas a partir da âncora; dia 31 → último dia de meses curtos e volta a 31;
  29/02 → 28/02 em anos comuns e volta a 29/02 nos bissextos.

## Dinheiro

- BRL, `BigDecimal`, nunca `Float`. Valores com 2 casas, arredondamento comercial (metade para cima), igual ao
  `round` do PostgreSQL usado nas constraints.
- Quantidades com 3 casas; custos unitários com 4 casas.
- Total da linha = arredondar(quantidade × preço, 2) − desconto; desconto nunca maior que a linha.
- Contas a receber: saldo = (valor − descontos) − (pago − estornado); sem pagamento acima do saldo, sem
  desconto acima do saldo, sem estorno acima do pago; cancelamento só sem valor retido.
- Fatura comercial e propostas não são nota fiscal.

## Custos e margem

- Custo médio móvel por depósito e item, recalculado em entradas, devoluções, transferências recebidas e
  ajustes de entrada (4 casas). Saídas usam o médio vigente e não o alteram.
- Consumo grava o custo do momento; compras posteriores não mudam o custo de ordens já executadas. Devoluções
  voltam ao custo do consumo original.
- Mão de obra: minutos × custo/hora vigente no apontamento (gravado no apontamento).
- Margem prevista: itens autorizados × custo unitário estimado. Margem realizada: faturado (líquido de
  descontos e cancelamentos) − material − mão de obra − despesas. Custos e margens só com `costs_view`.

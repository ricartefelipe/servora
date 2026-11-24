# Fluxos principais

## Orçamento → aprovação → ordem de serviço

```mermaid
sequenceDiagram
  actor A as Atendente
  participant S as Servora
  participant O as Outbox / jobs
  actor C as Contato do cliente
  A->>S: cria orçamento (rascunho, itens do catálogo)
  A->>S: envia versão
  S->>S: congela snapshot + digest (triggers impedem alteração)
  S->>O: quote.sent (mesma transação)
  O->>C: e-mail com link de uso único
  C->>S: GET do link (só confirma) e POST (cria sessão do portal)
  C->>S: aprova a versão vigente (digest conferido, evidências registradas)
  S->>O: quote.approved → notificações e webhooks
  A->>S: converte em ordem
  S->>S: INSERT … ON CONFLICT (uma ordem por versão) — repetir não duplica
```

## Execução da ordem

```mermaid
sequenceDiagram
  actor Co as Coordenação
  actor T as Técnico
  participant S as Servora
  Co->>S: agenda visita (técnico ou equipe)
  S->>S: reservas com EXCLUDE sobre tstzrange — conflito recusado no banco
  S->>S: SLA: primeira resposta cumprida
  T->>S: inicia visita, checklist, registro técnico, apontamentos (fila offline idempotente)
  T->>S: consome material (reserva ou estoque próprio, custo médio do momento)
  Co->>S: conclui (exige checklist, diagnóstico, solução, sem visita em andamento)
  S->>S: relatório versionado + SLA de resolução + liberação de reservas pela outbox
```

## Estoque

```mermaid
flowchart LR
  entrada["Entrada<br/>(recalcula custo médio)"] --> saldo[(Saldo<br/>físico · reservado · disponível)]
  saldo -- "reserva (lock: ordem → reserva → saldos ordenados)" --> reservado["Reservado para a ordem"]
  reservado -- consumo --> consumo["Consumo<br/>(custo do momento gravado)"]
  reservado -- "cancelamento/conclusão (outbox)" --> saldo
  consumo -- "devolução ao custo original" --> saldo
  saldo -- "transferência (duas pernas no mesmo savepoint)" --> saldo
  saldo -- "ajuste autorizado com motivo" --> saldo
```

Cada alteração de saldo grava um movimento append-only com o saldo resultante; o trigger do banco recusa
qualquer alteração sem movimento novo compatível.

## Contas a receber e cobrança

```mermaid
sequenceDiagram
  actor F as Financeiro
  participant S as Servora
  participant J as Job (fora de transação)
  participant P as Provedor (simulador ou Asaas)
  F->>S: emite conta (≤ total autorizado da ordem)
  F->>S: gera cobrança (pendente + evento outbox, referência externa estável)
  S->>J: payment_charge.requested
  J->>P: tentativa anterior? consulta pela referência : cria cobrança
  P-->>J: resposta (ou perda: situação "em verificação" e nova tentativa)
  P->>S: notificação (token) — gravada antes do 200, deduplicada
  S->>S: ConfirmCharge → pagamento idempotente (chave da cobrança)
  Note over S: conciliação a cada 5 minutos cobre confirmações perdidas
```

## Preventiva

1. Contrato vigente com plano (periodicidade, âncora, antecedência).
2. Job diário: para cada plano ativo, trava o plano, calcula as sequências devidas (até 12 por execução) e
   cria ocorrência + ordem por sequência; `(plano, sequência)` único impede duplicidade.
3. Mudança de calendário reancora na próxima sequência; ocorrências geradas não mudam.

# Servora

Plataforma SaaS B2B multitenant para gestão de serviços de campo e manutenção.

O Servora acompanha a operação de empresas de climatização, manutenção predial, assistência técnica e
manutenção de equipamentos comerciais — da solicitação do cliente à execução e ao resultado financeiro
de cada serviço, com histórico e rastreabilidade.

O estado de cada funcionalidade, com as evidências de teste, está em [`docs/STATUS.md`](docs/STATUS.md).

## Funcionalidades

- **Multitenancy com defesa em profundidade**: contexto de organização por transação, Row-Level Security em
  todas as tabelas de tenant, chaves estrangeiras compostas, papel de aplicação sem privilégios de bypass.
- **Identidade**: Devise com confirmação, bloqueio, sessões revogáveis e verificação em duas etapas; sete
  perfis com matriz de permissões; convites de uso único; auditoria com redação.
- **Clientes, locais e equipamentos** com histórico; **catálogo**; **orçamentos** versionados com snapshot
  imutável e aprovação pelo portal.
- **Ordens de serviço** com máquinas de estado, checklist, itens adicionais autorizados, relatórios versionados
  em PDF e anexos validados.
- **Agenda e despacho** com conflitos impedidos pelo PostgreSQL e reserva atômica de equipes; **SLA** com
  expediente, feriados, pausas e alertas.
- **Contratos e manutenção preventiva** com calendário ancorado e geração sem duplicidade.
- **Estoque** com razão append-only, reservas, consumo com custo histórico e proteção contra concorrência.
- **Financeiro**: contas a receber, pagamentos parciais idempotentes, descontos, estornos, margem prevista ×
  realizada e cobranças (simulador determinístico e Asaas sandbox).
- **Área do técnico (PWA)** com fila offline idempotente; **portal do cliente** com chamados e acompanhamento.
- **API v1** com OpenAPI, credenciais revogáveis e idempotência; **webhooks** assinados com proteção contra
  SSRF; notificações de pagamento deduplicadas.
- **Observabilidade**: logs JSON correlacionados e métricas Prometheus; **assinaturas** da plataforma com
  planos, módulos e avaliação.

## Stack

Ruby 4.0.10 · Rails 8.1 · PostgreSQL 18 · Hotwire (Turbo e Stimulus) · Tailwind CSS v4 ·
Solid Queue, Solid Cache e Solid Cable · Devise · Pundit · RSpec · Docker.

## Início rápido

```bash
cp .env.example .env
docker compose up --build
```

A aplicação fica em `http://localhost:3000`, que abre diretamente o formulário de acesso, e o Mailpit em
`http://localhost:58025`. O roteiro de
demonstração com as contas de exemplo está em [`docs/DEMO.md`](docs/DEMO.md).
Com `SERVORA_DEMO=1` (modo demonstração, desligado por padrão) a tela de acesso lista as contas de exemplo e a
senha, e a exigência de verificação em duas etapas não se aplica; nunca ative em uma instância com clientes reais.

Testes completos (regras puras, Rails, sistema e metas de cobertura): `bash bin/test-all`.
Guia completo de ambiente, testes e fluxo de contribuição: [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Documentação

- [Requisitos e critérios de aceite](docs/REQUISITOS.md)
- [Arquitetura](docs/ARQUITETURA.md) — multitenancy, máquinas de estado, matriz de permissões, módulos
- [C4: contexto e contêineres](docs/C4.md)
- [Modelo de dados](docs/MODELO-DE-DADOS.md)
- [Fluxos principais](docs/FLUXOS.md)
- [Políticas de calendário, dinheiro e custos](docs/POLITICAS.md)
- [API v1 (OpenAPI)](docs/api/openapi.yaml)
- [Runbooks, backup e restauração](docs/RUNBOOKS.md)
- [Roteiro de demonstração](docs/DEMO.md)
- [Decisões](docs/DECISOES.md)
- [Status](docs/STATUS.md)
- [Changelog](CHANGELOG.md)

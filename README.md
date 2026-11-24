# Servora

Plataforma SaaS B2B multitenant para gestão de serviços de campo e manutenção.

O Servora acompanha a operação de empresas de climatização, manutenção predial, assistência técnica e
manutenção de equipamentos comerciais — da solicitação do cliente à execução e ao resultado financeiro
de cada serviço, com histórico e rastreabilidade.

> Projeto em desenvolvimento. O estado de cada funcionalidade está em [`docs/STATUS.md`](docs/STATUS.md).

## Stack

Ruby 4.0.10 · Rails 8.1 · PostgreSQL 18 · Hotwire (Turbo e Stimulus) · Tailwind CSS v4 ·
Solid Queue, Solid Cache e Solid Cable · Devise · Pundit · RSpec · Docker.

## Início rápido

```bash
cp .env.example .env
docker compose up --build
```

A aplicação fica em `http://localhost:3000` e o Mailpit em `http://localhost:58025`.
Guia completo de ambiente, testes e fluxo de contribuição: [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Documentação

- [Requisitos e critérios de aceite](docs/REQUISITOS.md)
- [Arquitetura](docs/ARQUITETURA.md)
- [Decisões](docs/DECISOES.md)
- [Status](docs/STATUS.md)
- [Changelog](CHANGELOG.md)

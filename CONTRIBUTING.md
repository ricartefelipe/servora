# Contribuindo com o Servora

## Fluxo de branches (GitFlow)

| Branch | Origem | Destino | Uso |
|---|---|---|---|
| `main` | — | — | Versões estáveis de produção. Cada merge recebe tag anotada `vX.Y.Z`. |
| `develop` | — | — | Integração contínua do desenvolvimento. |
| `feature/<descricao>` | `develop` | `develop` | Uma funcionalidade ou fatia vertical. Nome em kebab-case. |
| `release/<x.y.z>` | `develop` | `main` e `develop` | Estabilização da versão; recebe apenas correções da versão. |
| `hotfix/<x.y.z>` | `main` | `main` e `develop` (e release ativa) | Correção urgente de produção. |

Regras:

1. Nunca desenvolva diretamente em `main` ou `develop`; toda alteração chega por pull request.
2. Crie a branch **antes** de alterar arquivos.
3. Merges preservam a branch no histórico (merge commit, equivalente a `--no-ff`). Squash e rebase
   estão desabilitados no repositório.
4. O merge só ocorre com todos os checks da CI aprovados e com as aprovações configuradas na proteção
   da branch.
5. Não faça force push em branches compartilhadas nem reescreva histórico publicado.
6. Após resolver conflitos, execute novamente as verificações afetadas.
7. Branches integradas são removidas (local e remotamente) para não deixar branches órfãs.
8. Release: `release/x.y.z` a partir de `develop` → atualizar `CHANGELOG.md` → PR para `main` →
   tag anotada `vX.Y.Z` no merge commit → PR de `release/x.y.z` para `develop` (reintegração).
9. Hotfix: `hotfix/x.y.z` a partir de `main` → PR para `main` → tag → PR para `develop` e para a
   release ativa, se houver.

O job `Fluxo de branches e commits` da CI (`script/ci/check_gitflow.rb`) valida nome, destino e
mensagens de commit de cada pull request.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/pt-br/v1.0.0/):

```
<tipo>(<escopo opcional>): <resumo no imperativo>
```

Tipos aceitos: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`,
`revert`. Use `!` ou `BREAKING CHANGE:` para quebras de compatibilidade. Commits pequenos e coerentes:
cada commit deve compilar e manter a suíte verde.

## Versionamento

[SemVer](https://semver.org/lang/pt-BR/). O `CHANGELOG.md` segue o formato *Keep a Changelog* e é
atualizado na branch de release.

## Ambiente local

Pré-requisitos: Docker com Compose, Ruby (versão em `.ruby-version`) e Chrome/Chromium para system specs.

```bash
cp .env.example .env
docker compose up -d db mailpit           # PostgreSQL 18 com papéis owner/app e Mailpit
bundle install
ruby bin/db-prepare --seed                # migrations (owner) + privilégios + seed (papel de aplicação)
RAILS_ENV=test ruby bin/db-prepare        # banco de testes
sh bin/dev                                # web, worker e Tailwind (foreman)
```

Ou tudo em containers:

```bash
docker compose up --build                 # db, mailpit, migrate (uma vez), web, worker, css
docker compose --profile test run --rm test
```

Interfaces locais: aplicação em `http://localhost:3000`, Mailpit em `http://localhost:58025`.

## Comandos de qualidade

| Comando | O que faz |
|---|---|
| `ruby bin/test-all` | Regras puras + specs Rails + system specs + metas de cobertura |
| `ruby bin/rspec-unit` | Apenas regras puras (sem Rails, banco, navegador ou rede) |
| `bundle exec rspec` | Specs com Rails (use `--seed <n>` para reproduzir uma ordem) |
| `ruby bin/coverage-check` | Consolida a cobertura e aplica as metas |
| `bundle exec rubocop` | Estilo e boas práticas (Rails, RSpec, performance) |
| `bundle exec brakeman` | Análise estática de segurança |
| `bundle exec bundler-audit check --update` | Vulnerabilidades conhecidas em gems |
| `SERVORA_DB_ROLE=owner ruby bin/rails db:migrate` | Nova migration (sempre com o papel owner) |

## Migrations e banco

- O esquema oficial é `db/structure.sql` (preserva RLS, constraints de exclusão, funções e triggers).
- Migrations rodam **somente** com o papel owner (`SERVORA_DB_ROLE=owner`); a aplicação usa o papel
  sem privilégios de bypass. Após migrar, `bin/db-prepare` reaplica os privilégios.
- Tabelas de tenant usam `Servora::MigrationHelpers#create_tenant_table`, que cria a chave
  `(organization_id, id)` e a policy de RLS. Referências entre tabelas de tenant usam
  `add_tenant_reference` (chave estrangeira composta).
- Toda migration precisa ser reversível; a CI executa rollback completo e compara o dump.

## Testes

- Regras puras ficam em `app/domain` e são testadas em `spec/unit` com `spec/unit_helper.rb`.
- Specs que dependem de commit real, locks ou concorrência usam a metadata `:committed`.
- Concorrência é testada com conexões separadas e barreiras (`Concurrent`/`Queue`), nunca com `sleep`.
- Fronteiras externas usam doubles verificáveis (`instance_double`) e WebMock; Active Record não é simulado
  quando o objetivo é provar constraints ou transações.

## Revisão do conteúdo

Antes de abrir um pull request, revise textos de interface, mensagens, comentários, documentação e
metadados: linguagem técnica e profissional, em português na interface e na documentação.

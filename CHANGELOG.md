# Changelog

Todas as mudanças relevantes são registradas aqui. Formato baseado em
[Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e versionamento [SemVer](https://semver.org/lang/pt-BR/).

## [Não lançado]

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

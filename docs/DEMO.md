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
| Gabriela Rocha | `gabriela@clima-norte.test` | Financeiro |
| Igor Martins | `igor@predial-sul.test` | Proprietário — Predial Sul (organização B) |

Perfis com verificação em duas etapas obrigatória (proprietário, administrador, financeiro) têm prazo de
carência para ativá-la; a demonstração pode seguir dentro do prazo.

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
13. **Ocorrência preventiva** — Contratos → "Manutenção preventiva — Loja Paulista" → plano "Preventiva mensal dos
    splits" → Gerar ocorrências devidas → a ordem preventiva nº 1 aparece vinculada ao contrato e coberta por ele.
    Gerar de novo não cria outra.
14. **Isolamento da organização B** — sair e entrar como Igor (Predial Sul): clientes, ordens, estoque e contas
    da Clima Norte não aparecem; acessar diretamente a URL de uma ordem da organização A retorna "não
    encontrado" (RLS no banco, além das policies).

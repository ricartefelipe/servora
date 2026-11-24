# frozen_string_literal: true

module Authorization
  # Renders the role x permission matrix documented in docs/ARQUITETURA.md.
  # A unit spec fails when the document diverges from Permissions::MATRIX.
  module PermissionMatrix
    LABELS = {
      organization_manage: "Configurar a organização",
      members_view: "Ver equipe",
      members_manage: "Gerenciar membros e convites",
      subscription_manage: "Gerenciar assinatura do Servora",
      customers_view: "Ver clientes e locais",
      customers_manage: "Gerenciar clientes e locais",
      equipment_view: "Ver equipamentos",
      equipment_manage: "Gerenciar equipamentos",
      catalog_view: "Ver catálogo (preço de venda)",
      catalog_manage: "Gerenciar catálogo",
      costs_view: "Ver custos internos e margens",
      quotes_view: "Ver orçamentos",
      quotes_manage: "Criar, versionar e enviar orçamentos",
      work_orders_view_all: "Ver todas as ordens de serviço",
      work_orders_manage: "Criar e gerenciar ordens",
      work_orders_execute: "Executar ordens atribuídas",
      work_orders_cancel: "Cancelar ordens",
      work_orders_reopen: "Reabrir ordens concluídas",
      additional_services_authorize: "Autorizar serviços adicionais",
      schedule_view: "Ver agenda",
      schedule_manage: "Agendar e despachar",
      contracts_view: "Ver contratos",
      contracts_manage: "Gerenciar contratos",
      preventive_manage: "Gerenciar planos preventivos",
      inventory_view: "Ver estoque",
      inventory_manage: "Movimentar estoque",
      inventory_adjust: "Ajustar saldos de estoque",
      finance_view: "Ver financeiro",
      finance_manage: "Gerenciar recebíveis e cobranças",
      finance_discount: "Conceder descontos",
      finance_refund: "Estornar pagamentos",
      reports_view: "Ver relatórios",
      integrations_manage: "Gerenciar integrações e API",
      audit_view: "Ver auditoria",
      outbox_reprocess: "Reprocessar eventos com falha"
    }.freeze

    ROLE_HEADERS = {
      "owner" => "Proprietário", "admin" => "Administrador", "coordinator" => "Coordenador",
      "attendant" => "Atendente", "technician" => "Técnico", "finance" => "Financeiro", "auditor" => "Auditor"
    }.freeze

    module_function

    def markdown
      header = "| Permissão | #{Permissions::ROLES.map { |role| ROLE_HEADERS.fetch(role) }.join(" | ")} |"
      divider = "|---|#{Permissions::ROLES.map { ":-:" }.join("|")}|"
      rows = Permissions::ALL.map do |permission|
        marks = Permissions::ROLES.map { |role| Permissions.granted?(role, permission) ? "✔" : "—" }
        "| #{LABELS.fetch(permission)} | #{marks.join(" | ")} |"
      end
      [header, divider, *rows].join("\n")
    end
  end
end

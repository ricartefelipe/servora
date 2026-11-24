# frozen_string_literal: true

# Sidebar entries. Each item declares the permission that makes it visible;
# authorization is still enforced by the controllers.
module NavigationHelper
  NavItem = Data.define(:label, :route, :icon, :permission, :controllers)

  NAVIGATION = [
    ["Operação", [
      NavItem.new("Painel", :dashboard_path, :dashboard, nil, %w[dashboards]),
      NavItem.new("Minha agenda", :field_root_path, :device, :work_orders_execute, %w[field/agenda field/work_orders]),
      NavItem.new("Ordens de serviço", :work_orders_path, :orders, nil, %w[work_orders checklist_items assignments visits]),
      NavItem.new("Agenda", :agenda_index_path, :calendar, :schedule_view, %w[agenda absences]),
      NavItem.new("Orçamentos", :quotes_path, :quote, :quotes_view, %w[quotes decisions]),
      NavItem.new("Contratos", :contracts_path, :preventive, :contracts_view, %w[contracts plans]),
      NavItem.new("Estoque", :stock_balances_path, :stock, :inventory_view,
        %w[stock_balances stock_movements warehouses receipts transfers adjustments]),
      NavItem.new("Financeiro", :receivables_path, :finance, :finance_view, %w[receivables payments discounts charges])
    ]],
    ["Cadastros", [
      NavItem.new("Clientes", :customers_path, :customers, :customers_view, %w[customers locations contacts]),
      NavItem.new("Equipamentos", :equipment_index_path, :equipment, :equipment_view, %w[equipment]),
      NavItem.new("Catálogo", :catalog_items_path, :catalog, :catalog_view, %w[catalog_items]),
      NavItem.new("Tipos de serviço", :service_types_path, :settings, :work_orders_manage, %w[service_types])
    ]],
    ["Gestão", [
      NavItem.new("Equipe", :members_path, :team, :members_view, %w[members invitations]),
      NavItem.new("Técnicos e equipes", :technicians_path, :wrench, :schedule_manage, %w[technicians teams]),
      NavItem.new("Auditoria", :audit_events_path, :audit, :audit_view, %w[audit_events]),
      NavItem.new("Eventos", :outbox_events_path, :integrations, :outbox_reprocess, %w[outbox_events]),
      NavItem.new("Pagamentos", :edit_payment_integration_path, :finance, :integrations_manage, %w[payment_integrations]),
      NavItem.new("Nota fiscal", :edit_fiscal_settings_path, :quote, :integrations_manage, %w[fiscal_settings]),
      NavItem.new("Integrações", :integrations_path, :integrations, :integrations_manage, %w[integrations]),
      NavItem.new("Prazos (SLA)", :sla_settings_path, :clock, :organization_manage, %w[sla_settings holidays]),
      NavItem.new("Assinatura", :subscription_path, :key, :subscription_manage, %w[subscriptions]),
      NavItem.new("Configurações", :edit_settings_path, :settings, :organization_manage, %w[settings])
    ]]
  ].freeze

  # Navigation entries that belong to an optional module of the subscription.
  MODULE_ROUTES = {
    stock_balances_path: :inventory, contracts_path: :preventive, receivables_path: :finance,
    edit_payment_integration_path: :finance, edit_fiscal_settings_path: :finance, integrations_path: :api
  }.freeze

  def navigation_groups
    NAVIGATION.filter_map do |title, items|
      visible = items.select { |item| item_visible?(item) }
      [title, visible] if visible.any?
    end
  end

  # Work orders are visible to office roles and to technicians (own orders).
  def item_visible?(item)
    return false if MODULE_ROUTES.key?(item.route) && !module_enabled?(MODULE_ROUTES.fetch(item.route))
    return can?(:work_orders_view_all) || can?(:work_orders_execute) if item.route == :work_orders_path

    item.permission.nil? || can?(item.permission)
  end

  # Entries with a namespace ("field/agenda") match the controller path; plain
  # names match controllers outside the field area.
  def nav_item_active?(item)
    item.controllers.any? do |name|
      name.include?("/") ? name == controller_path : name == controller_name && !controller_path.start_with?("field/")
    end
  end
end

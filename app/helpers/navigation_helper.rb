# frozen_string_literal: true

# Sidebar entries. Each item declares the permission that makes it visible;
# authorization is still enforced by the controllers.
module NavigationHelper
  NavItem = Data.define(:label, :route, :icon, :permission, :controllers)

  NAVIGATION = [
    ["Operação", [
      NavItem.new("Painel", :dashboard_path, :dashboard, nil, %w[dashboards]),
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
      NavItem.new("Prazos (SLA)", :sla_settings_path, :clock, :organization_manage, %w[sla_settings holidays]),
      NavItem.new("Configurações", :edit_settings_path, :settings, :organization_manage, %w[settings])
    ]]
  ].freeze

  def navigation_groups
    NAVIGATION.filter_map do |title, items|
      visible = items.select { |item| item_visible?(item) }
      [title, visible] if visible.any?
    end
  end

  # Work orders are visible to office roles and to technicians (own orders).
  def item_visible?(item)
    return can?(:work_orders_view_all) || can?(:work_orders_execute) if item.route == :work_orders_path

    item.permission.nil? || can?(item.permission)
  end

  def nav_item_active?(item)
    item.controllers.include?(controller_name)
  end
end

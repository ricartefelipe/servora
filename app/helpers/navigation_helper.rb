# frozen_string_literal: true

# Sidebar entries. Each item declares the permission that makes it visible;
# authorization is still enforced by the controllers.
module NavigationHelper
  NavItem = Data.define(:label, :route, :icon, :permission, :controllers)

  NAVIGATION = [
    ["Operação", [
      NavItem.new("Painel", :dashboard_path, :dashboard, nil, %w[dashboards])
    ]],
    ["Gestão", [
      NavItem.new("Equipe", :members_path, :team, :members_view, %w[members invitations]),
      NavItem.new("Auditoria", :audit_events_path, :audit, :audit_view, %w[audit_events]),
      NavItem.new("Configurações", :edit_settings_path, :settings, :organization_manage, %w[settings])
    ]]
  ].freeze

  def navigation_groups
    NAVIGATION.filter_map do |title, items|
      visible = items.select { |item| item.permission.nil? || can?(item.permission) }
      [title, visible] if visible.any?
    end
  end

  def nav_item_active?(item)
    item.controllers.include?(controller_name)
  end
end

# frozen_string_literal: true

module Authorization
  # Role → permission matrix. Pure data, shared by policies, views and the
  # permission matrix in docs/ARQUITETURA.md (kept in sync by spec).
  #
  # Sensitive permissions are explicit: internal costs and margins
  # (:costs_view), stock adjustments, discounts, refunds and audit access are
  # never granted implicitly by "manage" permissions.
  module Permissions
    ROLES = %w[owner admin coordinator attendant technician finance auditor].freeze

    # Roles that must enroll in multi-factor authentication.
    PRIVILEGED_ROLES = %w[owner admin finance].freeze

    ALL = %i[
      organization_manage members_view members_manage subscription_manage
      customers_view customers_manage
      equipment_view equipment_manage
      catalog_view catalog_manage costs_view
      quotes_view quotes_manage
      work_orders_view_all work_orders_manage work_orders_execute work_orders_cancel work_orders_reopen
      additional_services_authorize
      schedule_view schedule_manage
      contracts_view contracts_manage preventive_manage
      inventory_view inventory_manage inventory_adjust
      finance_view finance_manage finance_discount finance_refund
      reports_view integrations_manage audit_view outbox_reprocess
    ].freeze

    READ_ONLY = %i[
      members_view customers_view equipment_view catalog_view quotes_view work_orders_view_all
      schedule_view contracts_view inventory_view finance_view reports_view
    ].freeze

    MATRIX = {
      "owner" => ALL,
      "admin" => ALL - %i[subscription_manage],
      "coordinator" => %i[
        members_view customers_view customers_manage equipment_view equipment_manage catalog_view catalog_manage
        quotes_view quotes_manage work_orders_view_all work_orders_manage work_orders_cancel work_orders_reopen
        additional_services_authorize schedule_view schedule_manage contracts_view contracts_manage
        preventive_manage inventory_view inventory_manage reports_view
      ],
      "attendant" => %i[
        customers_view customers_manage equipment_view equipment_manage catalog_view quotes_view quotes_manage
        work_orders_view_all work_orders_manage schedule_view schedule_manage contracts_view inventory_view
      ],
      "technician" => %i[equipment_view catalog_view work_orders_execute schedule_view inventory_view],
      "finance" => %i[
        customers_view quotes_view work_orders_view_all catalog_view costs_view contracts_view inventory_view
        finance_view finance_manage finance_discount finance_refund reports_view
      ],
      "auditor" => READ_ONLY + %i[costs_view audit_view]
    }.transform_values { |permissions| permissions.to_set.freeze }.freeze

    module_function

    def granted?(role, permission)
      raise ArgumentError, "unknown permission: #{permission}" unless ALL.include?(permission)

      MATRIX.fetch(role.to_s) { Set.new }.include?(permission)
    end

    def for(role)
      MATRIX.fetch(role.to_s) { Set.new }
    end

    def privileged?(role)
      PRIVILEGED_ROLES.include?(role.to_s)
    end
  end
end

# frozen_string_literal: true

module Reports
  # Reports available to a member: permission and subscription module checks.
  module Catalog
    DEFINITIONS = {
      "ordens" => [WorkOrdersReport, nil, nil],
      "produtividade" => [ProductivityReport, nil, nil],
      "prazos" => [SlaReport, nil, nil],
      "financeiro" => [FinanceReport, :finance?, :finance],
      "materiais" => [MaterialsReport, :materials?, :inventory]
    }.freeze

    module_function

    # policy: ReportPolicy; module_enabled: ->(code) { … }
    def available(policy:, module_enabled:)
      DEFINITIONS.select do |_, (_, permission, mod)|
        (permission.nil? || policy.public_send(permission)) && (mod.nil? || module_enabled.call(mod))
      end.keys
    end

    def build(key, period:, zone:, show_costs:)
      DEFINITIONS.fetch(key).first.new(period:, zone:, show_costs:)
    end
  end
end

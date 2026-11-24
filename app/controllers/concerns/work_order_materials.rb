# frozen_string_literal: true

# Shared loading and feedback of the work order "Materiais" actions.
module WorkOrderMaterials
  extend ActiveSupport::Concern

  included do
    before_action :load_work_order

    rescue_from Servora::RuleViolation do |error|
      back_to_materials(alert: error.message)
    end

    rescue_from Pricing::Amount::InvalidValue do
      back_to_materials(alert: "Informe uma quantidade válida.")
    end
  end

  private

  def load_work_order
    @work_order = policy_scope(tenant_relation(WorkOrder)).includes(:assignments).find(params.expect(:work_order_id))
  end

  def back_to_materials(**flash)
    redirect_to work_order_path(@work_order, anchor: "materiais"), status: :see_other, **flash
  end

  # Client-generated operation identifiers are accepted only as UUIDs.
  def operation_key(value) = value.to_s[Servora::Tenancy::UUID_FORMAT]

  def stockable_items = tenant_relation(CatalogItem).stockable
  def operable_warehouses = policy_scope(tenant_relation(Warehouse)).active
end

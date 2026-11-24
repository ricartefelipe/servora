# frozen_string_literal: true

module Preventive
  # Creates or updates a plan. Changing the schedule (frequency, mode or
  # anchor) after occurrences were generated re-anchors the plan at the next
  # sequence: generated occurrences and their work orders are never touched.
  class SavePlan
    SCHEDULE_FIELDS = %w[frequency_unit frequency_interval schedule_mode anchor_date].freeze
    FIELDS = %i[title service_location_id service_type_id priority frequency_unit frequency_interval schedule_mode
                anchor_date lead_days instructions active].freeze

    def initialize(contract:, attributes:, actor:, plan: nil, equipment_ids: [])
      @contract = contract
      @plan = plan
      @attributes = attributes.to_h.symbolize_keys.slice(*FIELDS)
      @equipment_ids = Array(equipment_ids).compact_blank.uniq
      @actor = actor
    end

    def call
      raise Contracts::Errors::Invalid, "Contratos encerrados não recebem planos." if @contract.ended?

      ActiveRecord::Base.transaction(requires_new: true) do
        plan = @plan&.lock! || MaintenancePlan.new(organization_id: @contract.organization_id, contract: @contract,
          customer_id: @contract.customer_id, created_by: @actor)
        plan.assign_attributes(@attributes)
        reanchor(plan) if plan.persisted?
        validate_anchor!(plan)
        plan.save!
        replace_equipment(plan)
        AuditEvent.record!(action: @plan ? "maintenance_plan.updated" : "maintenance_plan.created", auditable: plan,
          changes: plan.saved_changes.except("updated_at", "lock_version"))
        plan
      end
    end

    private

    def reanchor(plan)
      return unless plan.last_sequence.positive? && SCHEDULE_FIELDS.any? { |field| plan.will_save_change_to_attribute?(field) }

      plan.anchor_sequence = plan.next_sequence
      last_due = MaintenanceOccurrence.where(maintenance_plan_id: plan.id).maximum(:due_on)
      return if plan.anchor_date > last_due

      raise Contracts::Errors::Invalid, "A nova data base deve ser posterior à última ocorrência gerada (#{I18n.l(last_due)})."
    end

    def validate_anchor!(plan)
      return if plan.anchor_date.blank? || plan.anchor_date >= @contract.starts_on

      raise Contracts::Errors::Invalid, "A data base não pode ser anterior ao início do contrato."
    end

    def replace_equipment(plan)
      ids = Equipment.where(id: @equipment_ids, customer_id: plan.customer_id).pluck(:id)
      MaintenancePlanEquipment.where(maintenance_plan_id: plan.id).where.not(equipment_id: ids).delete_all
      (ids - MaintenancePlanEquipment.where(maintenance_plan_id: plan.id).pluck(:equipment_id)).each do |equipment_id|
        MaintenancePlanEquipment.create!(organization_id: plan.organization_id, maintenance_plan: plan,
          customer_id: plan.customer_id, equipment_id:)
      end
    end
  end
end

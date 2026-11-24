# frozen_string_literal: true

module WorkOrders
  class Assign
    class NotTechnician < Servora::RuleViolation; end

    def initialize(work_order:, membership:, role: "technician")
      @work_order = work_order
      @membership = membership
      @role = role
    end

    def call
      raise NotTechnician, "Somente técnicos ativos podem ser atribuídos." unless @membership.active? && @membership.technician?

      assignment = @work_order.assignments.create_or_find_by!(membership: @membership) do |record|
        record.organization_id = @work_order.organization_id
        record.role = @role
      end
      AuditEvent.record!(action: "work_order.assigned", auditable: @work_order, changes: { membership_id: @membership.id })
      assignment
    end
  end
end

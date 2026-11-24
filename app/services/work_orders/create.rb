# frozen_string_literal: true

module WorkOrders
  # Opens a work order from a customer request (phone, e-mail, portal...).
  class Create
    def initialize(organization:, actor:, attributes:, equipment_ids: [], requires_approval: false)
      @organization = organization
      @actor = actor
      @attributes = attributes.to_h.symbolize_keys
      @equipment_ids = Array(equipment_ids).compact_blank
      @requires_approval = requires_approval
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        work_order = @organization.work_orders.create!(@attributes.merge(
          number: Numbering.next!(organization: @organization, scope: "work_order"), created_by: @actor,
          requested_at: @attributes[:requested_at] || Time.current, status: "open"
        ))
        Setup.new(work_order:, equipment_ids: @equipment_ids).call
        Transition.new(work_order:, to: @requires_approval ? "awaiting_approval" : "approved", actor: @actor).call
        AuditEvent.record!(action: "work_order.created", auditable: work_order, changes: { number: work_order.number })
        Outbox::Publisher.publish!(event_type: "work_order.created", aggregate: work_order)
        work_order
      end
    end
  end
end

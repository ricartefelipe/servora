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
        work_order = @organization.work_orders.create!(with_contract(@attributes).merge(
          number: Numbering.next!(organization: @organization, scope: "work_order"), created_by: @actor,
          requested_at: @attributes[:requested_at] || Time.current, status: "open"
        ))
        Setup.new(work_order:, equipment_ids: @equipment_ids).call
        Sla::Track.new(work_order).start
        Transition.new(work_order:, to: @requires_approval ? "awaiting_approval" : "approved", actor: @actor).call
        AuditEvent.record!(action: "work_order.created", auditable: work_order, changes: { number: work_order.number })
        Outbox::Publisher.publish!(event_type: "work_order.created", aggregate: work_order)
        work_order
      end
    end

    private

    # A work order without an explicit contract is linked to the customer's
    # contract in force that covers the service type, when there is one.
    def with_contract(attributes)
      return attributes if attributes.key?(:contract_id) || attributes[:customer_id].blank?

      contract = Contracts::Coverage.resolve(customer_id: attributes[:customer_id], service_type_id: attributes[:service_type_id],
        on: (attributes[:requested_at] || Time.current).to_date)
      contract ? attributes.merge(contract_id: contract.id) : attributes
    end
  end
end

# frozen_string_literal: true

module Portal
  # A customer contact opens a service request. It becomes a work order of the
  # contact's own customer, kept "open" for triage by the office, which is
  # notified after commit. Location and equipment must belong to the customer
  # (checked here and by composite foreign keys).
  class OpenRequest
    URGENCIES = { "normal" => "Normal", "high" => "Urgente — equipamento parado" }.freeze

    def initialize(contact:, title:, description:, service_location_id:, equipment_id: nil, urgency: "normal")
      @contact = contact
      @title = title.to_s.squish
      @description = description.to_s.strip
      @service_location_id = service_location_id
      @equipment_id = equipment_id.presence
      @urgency = URGENCIES.key?(urgency) ? urgency : "normal"
    end

    def call
      validate!
      ActiveRecord::Base.transaction(requires_new: true) do
        work_order = WorkOrders::Create.new(organization: @contact.organization, actor: nil, triage: true,
          attributes: attributes, equipment_ids: [equipment&.id].compact).call
        Outbox::Publisher.publish!(event_type: "work_order.requested", aggregate: work_order,
          dedup_key: "work_order.requested:#{work_order.id}")
        work_order
      end
    end

    private

    def validate!
      raise Servora::RuleViolation, "Descreva o pedido em poucas palavras." if @title.blank?
      raise Servora::RuleViolation, "Conte o que está acontecendo." if @description.blank?
      raise Servora::RuleViolation, "O texto é longo demais." if @title.size > 160 || @description.size > 5000
    end

    def location = @location ||= ServiceLocation.active.where(customer_id: @contact.customer_id).find(@service_location_id)
    def equipment = @equipment_id && Equipment.active.where(customer_id: @contact.customer_id).find(@equipment_id)

    def attributes
      { title: @title, problem_description: @description, origin: "portal", priority: @urgency,
        customer_id: @contact.customer_id, service_location_id: location.id, requested_by_contact_id: @contact.id }
    end
  end
end

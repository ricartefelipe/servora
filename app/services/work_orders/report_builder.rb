# frozen_string_literal: true

module WorkOrders
  # Frozen data of the execution report: what was diagnosed, done and used,
  # with the checklist answers at completion time. Internal costs excluded.
  class ReportBuilder
    def initialize(work_order)
      @work_order = work_order
    end

    def call
      {
        "work_order" => work_order_data, "customer" => customer_data, "location" => location_data,
        "equipment" => @work_order.equipment.map { |e| { "title" => e.title, "serial_number" => e.serial_number.to_s } },
        "problem" => @work_order.problem_description, "diagnosis" => @work_order.diagnosis.to_s,
        "solution" => @work_order.solution.to_s,
        "checklist" => @work_order.checklist_items.map { |c| { "label" => c.label, "response" => c.response.to_s } },
        "services" => services, "technicians" => @work_order.technicians.map { |m| m.user.name }
      }
    end

    private

    def work_order_data
      { "number" => @work_order.number, "title" => @work_order.title, "priority" => @work_order.priority,
        "requested_at" => @work_order.requested_at.iso8601, "completed_at" => Time.current.iso8601 }
    end

    def customer_data
      { "name" => @work_order.customer.name, "document" => @work_order.customer.document.to_s }
    end

    def location_data
      location = @work_order.service_location
      { "name" => location.name, "address" => location.address_line, "city" => location.city_line }
    end

    def services
      @work_order.items.authorized.map do |item|
        { "description" => item.description, "quantity" => item.quantity.to_s("F"), "unit" => item.unit }
      end
    end
  end
end

# frozen_string_literal: true

module Seeds
  module DemoActivity
    # Scheduling and execution side of a story: visits, checklist, technical
    # report, materials, additional items, time entries and expenses.
    module FieldActions
      # Readings used for numeric checklist items (label => value).
      READINGS = { "Pressão de sucção (psi)" => "118", "Corrente do compressor (A)" => "7,8" }.freeze

      private

      # Working hours are enforced on weekdays; when the demonstration day
      # falls on a weekend the visits are an on-call shift.
      def schedule(order:, on:, from:, to:, technicians:, team: nil)
        starts_at = instant(on, from)
        @ids[:visit][order] = Scheduling::ScheduleVisit.new(
          work_order: WorkOrder.includes(:organization).find(id_of(:order, order)), starts_at:, ends_at: instant(on, to),
          technicians: technicians.map { |key| member(key) }, actor: Current.membership,
          team: team && Team.find_by!(name: team), enforce_working_hours: starts_at.to_date.on_weekday?
        ).call.id
      end

      def travel(order:)
        Visits::Travel.new(visit: visit(order), actor: Current.membership).call
      end

      def start(order:)
        Visits::Start.new(visit: visit(order), actor: Current.membership).call
      end

      # Ends the visit and records the labor of every reserved technician.
      def finish(order:, outcome:, needs_return: false)
        record = visit(order)
        technicians = record.allocations.map(&:membership).uniq
        Visits::Finish.new(visit: record, actor: Current.membership, outcome_note: outcome, needs_return:).call
        work_order = order(order)
        technicians.each do |technician|
          TimeEntries::Record.new(work_order:, membership: technician, started_at: record.started_at, ended_at: Time.current,
            source: "field", visit: record).call
        end
      end

      # checklist: true answers every item not answered yet; false leaves them
      # for later. The reports of one order repeat its diagnosis (Living).
      def report(order:, diagnosis:, solution: nil, checklist: true, notes: nil)
        work_order = order(order)
        if checklist
          work_order.checklist_items.each do |item|
            next if item.response

            response = checklist_response(item, notes)
            WorkOrders::AnswerChecklist.new(item:, response:, actor: Current.membership).call if response
          end
        end
        WorkOrders::UpdateTechnicalReport.new(work_order: work_order.reload, diagnosis:, solution:).call
      end

      # One checklist answer recorded during the visit.
      def answer(order:, label:, response:)
        item = order(order).checklist_items.find { |candidate| candidate.label == label }
        WorkOrders::AnswerChecklist.new(item:, response:, actor: Current.membership).call
      end

      def checklist_response(item, notes)
        case item.response_kind
        when "check" then "sim"
        when "number" then READINGS.fetch(item.label, "0")
        else notes
        end
      end

      def reserve(order:, warehouse:, sku:, quantity:)
        @ids[:reservation][[order, sku]] = Inventory::Reserve.new(work_order: order(order), warehouse: warehouse(warehouse),
          item: catalog(sku), quantity:, actor: Current.membership).call.id
      end

      def consume(order:, warehouse:, sku:, quantity:, from_reservation: false)
        reservation = from_reservation ? StockReservation.find(id_of(:reservation, [order, sku])) : nil
        Inventory::Consume.new(work_order: order(order), warehouse: warehouse(warehouse), item: catalog(sku), quantity:,
          actor: Current.membership, reservation:, idempotency_key: operation_key("consumption", order, sku)).call
      end

      # Items found during execution; with a contact they are authorized by
      # the customer at once, otherwise they stay pending authorization.
      def items(order:, lines:, contact: nil, channel: "phone")
        work_order = order(order)
        lines.each do |sku, quantity|
          item = WorkOrders::AddItem.new(work_order:, actor: Current.membership, quantity:, catalog_item: catalog(sku)).call
          next unless contact

          WorkOrders::DecideItem.new(item:, decision: "authorized", actor: Current.membership, contact: contact(contact),
            channel:).call
        end
      end

      def wait_parts(order:, reason:)
        WorkOrders::ChangeStatus.new(work_order: order(order), to: "waiting_parts", actor: Current.membership, reason:).call
      end

      # The customer asked to wait (the resolution deadline is paused).
      def wait_customer(order:, reason:)
        WorkOrders::ChangeStatus.new(work_order: order(order), to: "waiting_customer", actor: Current.membership,
          reason:).call
      end

      # The customer called the visit off (the reservations are released).
      def cancel_visit(order:, reason:)
        Visits::Cancel.new(visit: visit(order), actor: Current.membership, reason:).call
      end

      # Same steps as WorkOrders::ExpensesController#create.
      def expense(order:, category:, description:, amount:)
        work_order = order(order)
        expense = Expense.create!(organization_id: work_order.organization_id, work_order:, category:, description:,
          amount: BigDecimal(amount), incurred_on: today, recorded_by_membership_id: Current.membership.id)
        AuditEvent.record!(action: "expense.recorded", auditable: work_order,
          changes: { category: expense.category, amount: expense.amount })
      end
    end
  end
end

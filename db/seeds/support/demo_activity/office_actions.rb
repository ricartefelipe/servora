# frozen_string_literal: true

module Seeds
  module DemoActivity
    # Office side of a story: customers, work orders, contracts, completion,
    # billing and stock (quotes are in QuoteActions). Each action is one use case call made by the
    # member given in the event (`by:`), at the event's instant.
    module OfficeActions
      private

      def register_customer(data:)
        Seeds.seed_customer(organization, data, today: @today)
      end

      # equipment_status: the state reported by the customer ("attention",
      # "inoperative"); completing the order puts the equipment back in operation.
      def open_order(key:, customer:, location:, title:, problem:, priority:, origin:, service_type: nil, equipment: [],
                     contact: nil, triage: false, equipment_status: nil)
        client = self.customer(customer)
        attributes = { title:, problem_description: problem, origin:, priority:, customer_id: client.id,
                       service_location_id: location(client, location).id, service_type_id: service_type(service_type)&.id,
                       requested_by_contact_id: contact && contact(contact).id }
        work_order = WorkOrders::Create.new(organization:, actor: Current.membership, attributes:,
          equipment_ids: equipment_ids(equipment), triage:).call
        @ids[:order][key] = work_order.id
        return unless equipment_status

        @ids[:affected][key] = equipment
        change_equipment(equipment, equipment_status, "Chamado da ordem #{work_order.number}: #{title}")
      end

      # A request opened by a customer contact in the portal (Portal::OpenRequest):
      # it stays "open" for triage by the office. urgency: "normal" or "high"
      # (equipment stopped); equipment_status: the state the customer reported,
      # recorded with the request (no member acting).
      def portal_request(key:, contact:, location:, title:, problem:, urgency:, equipment: nil, equipment_status: nil)
        person = contact(contact)
        work_order = Current.set(organization:, portal_contact: person) do
          Portal::OpenRequest.new(contact: person, title:, description: problem, urgency:,
            service_location_id: location(person.customer, location).id,
            equipment_id: equipment && equipment([equipment]).pick(:id)).call
        end
        @ids[:order][key] = work_order.id
        return unless equipment && equipment_status

        @ids[:affected][key] = [equipment]
        change_equipment([equipment], equipment_status, "Pedido do portal nº #{work_order.number}: #{title}")
      end

      # The office reviews a portal request and accepts it for scheduling,
      # classifying it first: the service type brings its checklist, answered
      # on the visit.
      def triage(order:, reason:, service_type: nil)
        work_order = order(order)
        classify(work_order, service_type(service_type)) if service_type && work_order.service_type_id.nil?
        WorkOrders::ChangeStatus.new(work_order:, to: "approved", actor: Current.membership, reason:).call
      end

      def classify(work_order, type)
        work_order.update!(service_type: type)
        WorkOrders::Setup.new(work_order:).call
        AuditEvent.record!(action: "work_order.updated", auditable: work_order, changes: { service_type: [nil, type.name] })
      end

      # A unit installed by the team (row as in Seeds::CUSTOMERS), registered
      # on the installation day.
      def register_equipment(customer:, row:)
        client = self.customer(customer)
        Seeds.seed_equipment(organization, client, { row[4] => location(client, row[4]) }, row, today)
      end

      def change_equipment(serials, status, reason)
        equipment(serials).each do |record|
          EquipmentLifecycle::ChangeStatus.new(equipment: record, status:, actor: Current.membership, reason:).call
        end
      end

      def complete(order:)
        work_order = WorkOrders::Complete.new(work_order: order(order), actor: Current.membership).call
        affected = @ids[:affected].fetch(order) { affected_by(order) }
        change_equipment(affected, "operational", "Ordem #{work_order.number} concluída") if affected
      end

      # Issues the remaining billable amount, or installment `part` = [index, count],
      # due `due_in` calendar days later (moved to the next business day).
      def bill(order:, key:, due_in:, part: nil)
        work_order = order(order)
        remaining = WorkOrderFinancialsQuery.new(work_order).remaining_to_bill
        amount = remaining
        description = nil
        if part
          index, count = part
          billable = WorkOrderFinancialsQuery.new(work_order).billable_total
          amount = (billable / count).round(2) if index < count
          description = "Ordem de serviço #{work_order.number} — parcela #{index}/#{count}"
        end
        @ids[:receivable][key] = Receivables::Issue.new(work_order:, amount:, due_on: settlement_day(today + due_in),
          actor: Current.membership, description:).call.id
      end

      def pay(receivable:, method:, amount: nil)
        record = Receivable.find(id_of(:receivable, receivable))
        Receivables::RegisterPayment.new(receivable: record, amount: amount || record.balance, payment_method: method,
          actor: Current.membership, idempotency_key: operation_key("payment", receivable, amount)).call
      end

      def receive_stock(warehouse:, sku:, quantity:, unit_cost:, reason:)
        Inventory::Receive.new(warehouse: warehouse(warehouse), item: catalog(sku), quantity:, unit_cost:,
          actor: Current.membership, reason:, idempotency_key: operation_key("receipt", warehouse, sku, reason)).call
      end

      # Weekly purchase of what the routine work used, at the catalog cost
      # times `factor` (the supplier's price of the week).
      def restock(warehouse:, sku:, quantity:, factor:, reason:)
        receive_stock(warehouse:, sku:, quantity:, unit_cost: (catalog(sku).unit_cost * BigDecimal(factor)).round(4), reason:)
      end

      # covers: names of the service types covered (the plan's type by default).
      def contract(key:, customer:, title:, attributes:, plan:, covers: nil)
        client = self.customer(customer)
        type = service_type(plan.fetch(:service_type))
        covered = (covers || [plan.fetch(:service_type)]).map { |name| service_type(name).id }
        contract = Contracts::Save.new(organization:, actor: Current.membership, service_type_ids: covered,
          attributes: attributes.merge(customer_id: client.id, title:, starts_on: today.beginning_of_month)).call
        contract = Contracts::ChangeStatus.new(contract:, to: "active", actor: Current.membership).call
        @ids[:plan][key] = save_plan(contract, client, type, plan).id
      end

      def save_plan(contract, client, type, plan)
        attributes = plan.except(:service_type, :location, :equipment, :anchor_in).merge(
          service_location_id: location(client, plan.fetch(:location)).id, service_type_id: type.id,
          anchor_date: @today + plan.fetch(:anchor_in)
        )
        Preventive::SavePlan.new(contract:, actor: Current.membership, equipment_ids: equipment_ids(plan.fetch(:equipment)),
          attributes:).call
      end

      # The daily preventive job (no member acting).
      def generate(plan:, order:)
        occurrence = Preventive::GenerateOccurrences.new(plan: MaintenancePlan.find(id_of(:plan, plan)), today:).call.first
        @ids[:order][order] = occurrence.work_order_id
      end
    end
  end
end

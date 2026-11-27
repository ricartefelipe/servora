# frozen_string_literal: true

module Seeds
  module DemoActivity
    # A record of the story that cannot be found (changed or removed since).
    class Unresolved < StandardError; end

    # The records a story works with: those created by its own events (by key,
    # see #id_of) and the registration data it refers to (customers, catalog,
    # warehouses...).
    #
    # While a story is replayed, each event that creates a record keeps its
    # identifier. When the story advances later (Living), those identifiers
    # are found again from the event that created the record, by the instant
    # that event wrote into it: [kind, key] => [instant, action, params].
    module StoryRecords
      # Actions that create a work order, with the parameter that holds its key.
      CREATES = { open_order: :key, portal_request: :key, convert_quote: :order, generate: :order }.freeze

      private

      # Identifier of a record created by an earlier event: kept while the
      # story is replayed, or found again from the event that created it
      # (#locate) when the story advances after being recorded (Living).
      def id_of(kind, key)
        @ids[kind].fetch(key) do
          @ids[kind][key] = locate(kind, key) || raise(Unresolved, "#{kind} #{key.inspect} not found")
        end
      end

      def order(key) = WorkOrder.find(id_of(:order, key))
      def visit(key) = Visit.includes(allocations: :membership).find(id_of(:visit, key))
      def customer(document) = reference(:customer, document) { Customer.find_by!(document:) }
      def contact(email) = reference(:contact, email) { CustomerContact.find_by!(email:) }
      def catalog(sku) = reference(:catalog, sku) { CatalogItem.find_by!(sku:) }
      def warehouse(name) = reference(:warehouse, name) { Warehouse.find_by!(name:) }
      def service_type(name) = name && reference(:service_type, name) { ServiceType.find_by!(name:) }
      def equipment(serials) = Equipment.where(serial_number: serials).order(:serial_number)
      def equipment_ids(serials) = reference(:equipment, serials) { equipment(serials).pluck(:id) }

      def location(customer, name)
        reference(:location, [customer.id, name]) { ServiceLocation.find_by!(customer_id: customer.id, name:) }
      end

      # Registration data (customers, locations, contacts, catalog, warehouses,
      # service types, equipment) does not change while a story is replayed:
      # each record is read once.
      def reference(kind, key)
        references = (@references ||= Hash.new { |hash, name| hash[name] = {} })[kind]
        references.fetch(key) { references[key] = yield }
      end

      # Deterministic idempotency key of a seeded operation.
      def operation_key(*parts)
        Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, ["servora-demo", @organization_id, *parts].join(":"))
      end

      # [kind, key] => [instant, action, params] of the event that created it.
      def index_creators
        @creators = {}
        timeline.each do |time, _, action, params|
          created = created_by(action, params)
          @creators[created] = [time, action, params] if created
        end
      end

      def created_by(action, params)
        case action
        when *CREATES.keys then [:order, params.fetch(CREATES.fetch(action))]
        when :schedule then [:visit, params[:order]]
        when :bill then [:receivable, params[:key]]
        when :reserve then [:reservation, [params[:order], params[:sku]]]
        when :quote then [:quote, params[:key]]
        end
      end

      # Finds again a record created by an earlier event, by the instant the
      # event wrote into it (nil when it does not exist, or not any more).
      def locate(kind, key)
        time, _, params = @creators&.[]([kind, key])
        time && send(:"locate_#{kind}", key, time, params)
      end

      def locate_order(_key, time, params)
        WorkOrder.where(created_at: time).where(params[:title] ? { title: params[:title] } : {}).pick(:id)
      end

      def locate_visit(key, _time, params)
        Visit.where(work_order_id: id_of(:order, key), scheduled_start: instant(params[:on], params[:from])).pick(:id)
      end

      def locate_receivable(_key, time, params)
        Receivable.where(work_order_id: id_of(:order, params[:order]), created_at: time).pick(:id)
      end

      def locate_reservation((order_key, sku), time, _params)
        StockReservation.where(work_order_id: id_of(:order, order_key), catalog_item_id: catalog(sku).id, created_at: time)
          .pick(:id)
      end

      def locate_quote(_key, time, params) = Quote.where(created_at: time, title: params[:title]).pick(:id)

      # Equipment put out of operation by the request of `order`.
      def affected_by(order)
        _, action, params = @creators&.[]([:order, order])
        return nil unless params && %i[open_order portal_request].include?(action) && params[:equipment_status]

        Array(params[:equipment])
      end
    end
  end
end

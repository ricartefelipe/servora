# frozen_string_literal: true

module WorkOrders
  # Converts an approved quote into a work order. Idempotent, including under
  # concurrent requests: the insert uses ON CONFLICT DO NOTHING on the unique
  # (organization_id, quote_version_id) index; the loser of a race waits for
  # the winner's commit and then returns the existing work order.
  class CreateFromQuote
    class NotConvertible < Servora::RuleViolation; end

    Result = Data.define(:work_order, :created)
    COPIED_ITEM_FIELDS = %w[organization_id kind description unit quantity unit_price unit_cost discount_amount line_total
                            catalog_item_id].freeze

    def initialize(quote:, actor:)
      @quote = quote
      @actor = actor
    end

    def call
      version_id = @quote.approved_version_id
      raise NotConvertible, "Somente orçamentos aprovados podem gerar ordem de serviço." unless version_id && converting_allowed?

      ActiveRecord::Base.transaction(requires_new: true) do
        created_id = insert_work_order(version_id)
        work_order = WorkOrder.find_by!(quote_version_id: version_id)
        complete_conversion(work_order) if created_id
        Result.new(work_order:, created: created_id.present?)
      end
    end

    private

    def converting_allowed?
      @quote.approved? || @quote.converted?
    end

    def insert_work_order(version_id)
      now = Time.current
      attributes = {
        organization_id: @quote.organization_id, quote_version_id: version_id, customer_id: @quote.customer_id,
        service_location_id: @quote.service_location_id,
        number: Numbering.next!(organization: @quote.organization, scope: "work_order"),
        title: @quote.title, origin: "quote", priority: "normal", status: "open", created_by_membership_id: @actor.id,
        problem_description: "Execução do orçamento #{@quote.number}.", requested_at: now, created_at: now, updated_at: now
      }
      # Conflict-tolerant insert: this is the idempotency mechanism.
      WorkOrder.insert(attributes, unique_by: :index_work_orders_one_per_quote_version, returning: :id) # rubocop:disable Rails/SkipsModelValidations
        .rows.first&.first
    end

    def complete_conversion(work_order)
      copy_items(work_order)
      Transition.new(work_order:, to: "approved", actor: @actor, reason: "Orçamento #{@quote.number} aprovado").call
      @quote.update!(status: "converted")
      Quotes::History.record!(@quote, kind: "converted", note: work_order.number)
      AuditEvent.record!(action: "work_order.created", auditable: work_order,
        changes: { number: work_order.number, quote: @quote.number })
      Outbox::Publisher.publish!(event_type: "work_order.created", aggregate: work_order)
    end

    def copy_items(work_order)
      version = QuoteVersion.includes(:items, :decided_by_contact).find(@quote.approved_version_id)
      authorization = {
        source: "quote", authorization_status: "authorized", authorized_at: version.decided_at, authorization_channel: "quote",
        authorized_by_contact_id: version.decided_by_contact_id, authorized_by_membership_id: @actor.id,
        authorization_note: "#{@quote.number} · #{version.label}"
      }
      version.items.each { |item| work_order.items.create!(item.attributes.slice(*COPIED_ITEM_FIELDS).merge(authorization)) }
    end
  end
end

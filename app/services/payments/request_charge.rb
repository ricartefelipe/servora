# frozen_string_literal: true

module Payments
  # Creates a charge for the open balance of a receivable. Nothing is sent to
  # the provider here: the charge is stored as pending together with an outbox
  # event, and the submission runs after commit, outside any transaction.
  class RequestCharge
    def initialize(receivable:, actor:, billing_type: nil)
      @receivable = receivable
      @actor = actor
      @billing_type = billing_type.presence
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        Receivables::Errors.lock_outstanding!(@receivable)
        raise Receivables::Errors::Invalid, "A conta já está quitada." if @receivable.position.settled?

        create_charge
      end
    rescue ActiveRecord::RecordNotUnique
      raise Receivables::Errors::Invalid, "Já existe uma cobrança em andamento para esta conta."
    end

    private

    def create_charge
      integration = PaymentIntegration.for(@receivable.organization_id)
      billing_type = @billing_type || integration.default_billing_type
      raise Receivables::Errors::Invalid, "Forma de cobrança inválida." unless PaymentCharge::BILLING_TYPES.key?(billing_type)

      charge = PaymentCharge.create!(organization_id: @receivable.organization_id, receivable: @receivable,
        provider: integration.provider, external_reference: "srv-#{SecureRandom.uuid_v7}", billing_type:,
        amount: @receivable.balance, due_on: [@receivable.due_on, Time.zone.today].max)
      FinancialEvent.record!(receivable: @receivable, kind: "charge_requested", amount: charge.amount, actor: @actor,
        details: { provider: charge.provider, billing_type: })
      Outbox::Publisher.publish!(event_type: "payment_charge.requested", aggregate: charge,
        dedup_key: "payment_charge.requested:#{charge.id}")
      charge
    end
  end
end

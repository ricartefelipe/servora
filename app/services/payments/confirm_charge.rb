# frozen_string_literal: true

module Payments
  # Turns a provider confirmation into a payment. Safe to run any number of
  # times (polling, webhook, manual simulation): the payment idempotency key is
  # derived from the charge. Lock order: receivable → charge.
  class ConfirmCharge
    def initialize(organization_id:, charge_id:, paid_at: nil, actor: nil)
      @organization_id = organization_id
      @charge_id = charge_id
      @paid_at = paid_at
      @actor = actor
    end

    def call
      Servora::Tenancy.with_organization(@organization_id) do
        charge = PaymentCharge.find(@charge_id)
        receivable = Receivable.lock("FOR NO KEY UPDATE").find(charge.receivable_id)
        charge.lock!
        confirm(receivable, charge)
      end
    end

    private

    def confirm(receivable, charge)
      return charge if charge.status == "confirmed"

      payment = register_payment(receivable, charge)
      charge.update!(status: "confirmed", confirmed_at: Time.current, last_synced_at: Time.current)
      FinancialEvent.record!(receivable:, kind: "charge_confirmed", amount: charge.amount, payment:, actor: @actor,
        details: payment ? {} : { attention: "Pagamento recebido para conta sem saldo; avaliar estorno no provedor." })
      charge
    end

    def register_payment(receivable, charge)
      return nil if receivable.canceled? || receivable.position.settled?

      amount = [charge.amount, receivable.balance].min
      Receivables::RegisterPayment.new(receivable:, amount:, payment_method: charge.billing_type, actor: @actor,
        paid_at: [@paid_at || Time.current, Time.current].min, idempotency_key: "charge:#{charge.id}", charge:).call
    end
  end
end

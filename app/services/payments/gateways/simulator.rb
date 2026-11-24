# frozen_string_literal: true

module Payments
  module Gateways
    # Deterministic provider for development, demonstrations and tests. No
    # network. The amount's cents select the scenario:
    #
    # * ,66 → the charge is refused;
    # * ,13 → the first submission loses its response (ambiguous), although the
    #         simulated provider kept the charge — the retry finds it by
    #         reference instead of creating a duplicate;
    # * any other value → the charge is registered and awaits payment.
    #
    # Payment confirmation is triggered explicitly ("simular pagamento").
    class Simulator
      REJECTED_CENTS = 66
      AMBIGUOUS_CENTS = 13

      def create_charge(charge, _customer)
        raise Errors::Rejected, "Cobrança recusada pelo simulador (valor terminado em ,66)." if cents(charge) == REJECTED_CENTS
        if cents(charge) == AMBIGUOUS_CENTS && charge.attempts <= 1
          raise Errors::AmbiguousResponse, "Tempo esgotado aguardando o simulador (valor terminado em ,13)."
        end

        remote(charge, "submitted")
      end

      def find_charge(charge)
        return nil unless charge.external_id.present? || cents(charge) == AMBIGUOUS_CENTS

        remote(charge, charge.status == "confirmed" ? "confirmed" : "submitted")
      end

      def cancel_charge(_charge) = nil

      private

      def cents(charge) = ((charge.amount * 100) % 100).to_i

      def remote(charge, status)
        RemoteCharge.new(external_id: "sim_#{charge.external_reference}", status:, payment_url: nil,
          paid_at: nil, amount: charge.amount)
      end
    end
  end
end

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

      # NFS-e: ,66 rejected by the "city hall"; ,13 loses the first response but
      # the invoice exists (found by reference); otherwise authorized at once.
      def issue_invoice(invoice, _customer, _settings, _charge)
        cents = ((invoice.amount * 100) % 100).to_i
        if cents == REJECTED_CENTS
          return remote_invoice(invoice, "error", message: "Prefeitura recusou a nota (valor terminado em ,66).")
        end
        if cents == AMBIGUOUS_CENTS && invoice.attempts <= 1
          raise Errors::AmbiguousResponse,
            "Tempo esgotado aguardando o simulador (valor terminado em ,13)."
        end

        remote_invoice(invoice, "authorized")
      end

      def find_invoice(invoice)
        return nil unless invoice.external_id.present? || ((invoice.amount * 100) % 100).to_i == AMBIGUOUS_CENTS

        remote_invoice(invoice, invoice.status == "canceling" ? "canceled" : "authorized")
      end

      def cancel_invoice(invoice) = remote_invoice(invoice, "canceled")

      # Same cents rule applied to the refund amount.
      def refund_charge(_charge, refund)
        cents = ((refund.amount * 100) % 100).to_i
        raise Errors::Rejected, "Estorno recusado pelo simulador (valor terminado em ,66)." if cents == REJECTED_CENTS
        if cents == AMBIGUOUS_CENTS
          raise Errors::AmbiguousResponse,
            "Tempo esgotado aguardando o simulador (valor terminado em ,13)."
        end

        RemoteRefund.new(external_id: "sim_refund_#{refund.id}", status: "accepted")
      end

      private

      def cents(charge) = ((charge.amount * 100) % 100).to_i

      def remote_invoice(invoice, status, message: nil)
        number = invoice.external_reference.delete("^0-9").last(8)
        RemoteInvoice.new(external_id: "sim_nfse_#{invoice.external_reference}", status:, number: (if status == "authorized"
                                                                                                     number
                                                                                                   end),
          verification_code: ("SIM#{number.first(4)}" if status == "authorized"), pdf_url: nil, xml_url: nil, message:)
      end

      def remote(charge, status)
        RemoteCharge.new(external_id: "sim_#{charge.external_reference}", status:, payment_url: nil,
          paid_at: nil, amount: charge.amount)
      end
    end
  end
end

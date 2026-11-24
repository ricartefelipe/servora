# frozen_string_literal: true

# Execution of a refund at the payment provider (or by the finance team for
# manual payments). The money movement itself is already recorded on the
# receivable by Receivables::RefundPayment.
class PaymentRefund < TenantRecord
  STATUSES = { "manual" => "Executar manualmente", "pending" => "Enviando ao provedor", "accepted" => "Aceito pelo provedor",
               "unknown" => "Em verificação", "failed" => "Recusado pelo provedor" }.freeze

  belongs_to :payment
  belongs_to :receivable

  def status_label = STATUSES.fetch(status)
  def needs_attention? = %w[unknown failed manual].include?(status)
end

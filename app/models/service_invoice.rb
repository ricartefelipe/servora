# frozen_string_literal: true

# NFS-e of a receivable, issued through the payment provider.
class ServiceInvoice < TenantRecord
  STATUSES = {
    "pending" => "Aguardando envio", "scheduled" => "Em processamento na prefeitura", "authorized" => "Autorizada",
    "unknown" => "Em verificação", "error" => "Rejeitada", "canceling" => "Cancelamento solicitado", "canceled" => "Cancelada"
  }.freeze
  VALID_STATUSES = %w[pending scheduled authorized unknown].freeze

  belongs_to :receivable, inverse_of: :service_invoices

  scope :valid, -> { where(status: VALID_STATUSES) }

  def status_label = STATUSES.fetch(status)
  def authorized? = status == "authorized"
end

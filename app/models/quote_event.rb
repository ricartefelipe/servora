# frozen_string_literal: true

# Negotiation history entry (append-only).
class QuoteEvent < TenantRecord
  KIND_LABELS = {
    "created" => "Orçamento criado", "version_created" => "Nova versão criada", "sent" => "Versão enviada ao cliente",
    "approved" => "Aprovado", "rejected" => "Recusado", "expired" => "Validade expirada", "comment" => "Comentário",
    "portal_link_sent" => "Link do portal enviado", "converted" => "Convertido em ordem de serviço", "canceled" => "Cancelado"
  }.freeze

  belongs_to :quote, inverse_of: :events
  belongs_to :quote_version, optional: true

  validates :kind, inclusion: { in: KIND_LABELS.keys }

  def readonly? = persisted?
  def kind_label = KIND_LABELS.fetch(kind)
end

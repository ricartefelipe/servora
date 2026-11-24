# frozen_string_literal: true

class WebhookDelivery < TenantRecord
  STATUSES = { "pending" => "Pendente", "delivered" => "Entregue", "failed" => "Falhou" }.freeze

  belongs_to :webhook_endpoint, inverse_of: :deliveries

  scope :recent_first, -> { order(created_at: :desc) }

  def status_label = STATUSES.fetch(status)
end

# frozen_string_literal: true

# Receiver of outbound webhooks. The signing secret is encrypted at rest and
# shown once. URLs are validated against SSRF (public HTTPS hosts only) on
# save and again, with the resolved address pinned, at every delivery.
class WebhookEndpoint < TenantRecord
  EVENTS = {
    "work_order.created" => "Ordem de serviço aberta", "work_order.completed" => "Ordem de serviço concluída",
    "work_order.canceled" => "Ordem de serviço cancelada", "quote.approved" => "Orçamento aprovado",
    "quote.rejected" => "Orçamento recusado"
  }.freeze

  encrypts :secret

  has_many :deliveries, class_name: "WebhookDelivery", dependent: nil, inverse_of: :webhook_endpoint

  validates :url, presence: true, length: { maximum: 500 }
  validates :description, length: { maximum: 120 }
  validate :safe_url
  validate :known_events

  scope :active, -> { where(active: true) }
  scope :subscribed_to, ->(event_type) { active.where("? = ANY(events)", event_type) }

  def self.generate_secret = "whsec_#{SecureRandom.urlsafe_base64(32)}"

  private

  def safe_url
    Webhooks::SafeUrl.check!(url) if url.present?
  rescue Webhooks::SafeUrl::Unsafe => e
    errors.add(:url, e.message)
  end

  def known_events
    errors.add(:events, "selecione ao menos um evento") if events.blank?
    errors.add(:events, "contém evento desconhecido") if (events - EVENTS.keys).any?
  end
end

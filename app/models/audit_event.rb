# frozen_string_literal: true

# Immutable audit record. Use AuditEvent.record! from use cases; it reads the
# actor and correlation data from Current and redacts sensitive values.
class AuditEvent < TenantRecord
  ACTOR_TYPES = %w[user portal_contact api_credential system].freeze

  belongs_to :auditable, polymorphic: true, optional: true

  validates :action, presence: true, length: { maximum: 80 }
  validates :actor_type, inclusion: { in: ACTOR_TYPES }

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def readonly?
    persisted?
  end

  def self.record!(action:, organization: Current.organization, auditable: nil, changes: {}, metadata: {})
    create!(
      organization_id: auditable.try(:organization_id) || organization&.id,
      action:,
      auditable_type: auditable&.class&.polymorphic_name,
      auditable_id: auditable&.id,
      changeset: Audit::Redactor.redact(changes.to_h),
      metadata: Audit::Redactor.redact(correlation_metadata.merge(metadata.to_h)),
      **actor_attributes
    )
  end

  def self.actor_attributes
    {
      actor_type: Current.actor_type,
      actor_user_id: Current.user&.id,
      actor_membership_id: Current.membership&.id,
      actor_label: Current.actor_label
    }
  end

  def self.correlation_metadata
    { request_id: Current.request_id, ip_address: Current.ip_address }.compact
  end

  private_class_method :actor_attributes, :correlation_metadata
end

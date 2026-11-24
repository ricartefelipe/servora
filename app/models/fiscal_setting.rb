# frozen_string_literal: true

# Municipal service data used to issue NFS-e through the payment provider.
# The municipal registration itself is configured in the provider account.
class FiscalSetting < TenantRecord
  normalizes :municipal_service_code, :municipal_service_name, with: ->(value) { value.to_s.squish }

  validates :municipal_service_code, presence: true, length: { maximum: 30 }
  validates :municipal_service_name, presence: true, length: { maximum: 250 }
  validates :iss_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }
  validates :default_description, length: { maximum: 500 }

  def self.for(organization_id) = find_by(organization_id:)
end

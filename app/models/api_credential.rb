# frozen_string_literal: true

# Revocable, scoped credential of the public API. Only the SHA-256 digest of
# the token is stored; the token is shown once, at creation.
class ApiCredential < TenantRecord
  SCOPES = {
    "customers:read" => "Ler clientes", "equipment:read" => "Ler equipamentos",
    "work_orders:read" => "Ler ordens de serviço", "work_orders:write" => "Abrir ordens de serviço",
    "receivables:read" => "Ler contas a receber"
  }.freeze

  belongs_to :created_by, class_name: "Membership", foreign_key: :created_by_membership_id, inverse_of: false

  validates :name, presence: true, length: { maximum: 80 }
  validate :known_scopes

  scope :usable, -> { where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def self.digest(token) = OpenSSL::Digest::SHA256.hexdigest(token.to_s)
  def self.generate_token = "svk_#{SecureRandom.urlsafe_base64(36)}"

  def self.organization_for(token)
    return nil if token.blank?

    connection.select_value(sanitize_sql_array(["SELECT servora_resolve_api_credential(?)", digest(token)]))
  end

  def usable? = revoked_at.nil? && (expires_at.nil? || expires_at.future?)
  def allows?(scope) = scopes.include?(scope)

  private

  def known_scopes
    errors.add(:scopes, "selecione ao menos um escopo") if scopes.blank?
    errors.add(:scopes, "contém escopo desconhecido") if (scopes - SCOPES.keys).any?
  end
end

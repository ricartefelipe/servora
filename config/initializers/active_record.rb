# Every datetime column is stored as timestamptz: scheduling ranges (tstzrange),
# SLA clocks and organization time zones depend on absolute instants.
ActiveSupport.on_load(:active_record_postgresqladapter) do
  self.datetime_type = :timestamptz
end

Rails.application.configure do
  # Encryption keys for integration credentials and MFA secrets. Production keys
  # come from the secret manager (validated in required_environment.rb). Local
  # environments derive throwaway keys that protect nothing of value.
  encryption = config.active_record.encryption
  if Rails.env.production?
    encryption.primary_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY", nil)
    encryption.deterministic_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY", nil)
    encryption.key_derivation_salt = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT", nil)
  else
    local_key = ->(purpose) { Digest::SHA256.hexdigest("servora-local-#{Rails.env}-#{purpose}") }
    encryption.primary_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY") { local_key.call("primary") }
    encryption.deterministic_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY") { local_key.call("deterministic") }
    encryption.key_derivation_salt = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT") { local_key.call("salt") }
  end
  encryption.support_unencrypted_data = false
  encryption.encrypt_fixtures = true
end

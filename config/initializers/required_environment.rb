# frozen_string_literal: true

# Fail fast in production when mandatory configuration is missing, instead of
# discovering it on the first request.
if Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
  role_prefix = ENV.fetch("SERVORA_DB_ROLE", "app") == "owner" ? "DB_OWNER" : "DB_APP"
  required = %W[
    SECRET_KEY_BASE APP_HOST #{role_prefix}_USER #{role_prefix}_PASSWORD
    ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
    ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
  ]
  missing = required.select { |name| ENV[name].blank? }
  raise "Missing required environment variables: #{missing.join(", ")}" if missing.any?
end

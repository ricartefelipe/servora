require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Private object storage (S3-compatible). See config/storage.yml.
  config.active_storage.service = ENV.fetch("ACTIVE_STORAGE_SERVICE", "object_storage").to_sym

  config.assume_ssl = ENV.fetch("ASSUME_SSL", "true") == "true"
  config.force_ssl = ENV.fetch("FORCE_SSL", "true") == "true"
  config.ssl_options = { redirect: { exclude: ->(request) { request.path.in?(%w[/up /ready]) } } }

  config.logger = ActiveSupport::TaggedLogging.logger($stdout)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.silence_healthcheck_path = "/up"
  config.active_support.report_deprecations = false

  config.cache_store = :solid_cache_store
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address: ENV.fetch("SMTP_ADDRESS", nil),
    port: Integer(ENV.fetch("SMTP_PORT", "587")),
    user_name: ENV.fetch("SMTP_USERNAME", nil),
    password: ENV.fetch("SMTP_PASSWORD", nil),
    authentication: ENV.fetch("SMTP_AUTHENTICATION", "plain").to_sym,
    enable_starttls_auto: true,
    open_timeout: 5,
    read_timeout: 10
  }.compact
  config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "servora.example"), protocol: "https" }

  config.i18n.fallbacks = true
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [:id]

  config.hosts = ENV.fetch("APP_HOSTS", ENV.fetch("APP_HOST", "")).split(",").map(&:strip).compact_blank
  config.host_authorization = { exclude: ->(request) { request.path.in?(%w[/up /ready]) } }
end

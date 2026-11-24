Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = ENV["CI"].present?

  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }
  config.consider_all_requests_local = true

  # Rate limiting needs a real store to be exercised in request specs.
  config.cache_store = :memory_store

  config.action_dispatch.show_exceptions = :rescuable
  config.action_controller.allow_forgery_protection = false

  config.active_storage.service = :test
  config.active_job.queue_adapter = :test

  config.action_mailer.delivery_method = :test
  config.action_mailer.default_url_options = { host: "servora.test" }

  config.active_support.deprecation = :raise
  config.active_record.verbose_query_logs = false
  config.action_controller.raise_on_missing_callback_actions = true
  config.i18n.raise_on_missing_translations = true
end

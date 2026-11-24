require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "action_cable/engine"

Bundler.require(*Rails.groups)

require_relative "../lib/servora/version"

module Servora
  class Application < Rails::Application
    config.load_defaults 8.1

    # lib/servora/version.rb defines Servora::VERSION and is required above.
    config.autoload_lib(ignore: %w[assets tasks servora/version.rb])

    # Product defaults: Portuguese UI, BRL, organization-specific time zones are
    # applied per request from the organization record.
    config.i18n.available_locales = [:"pt-BR"]
    config.i18n.default_locale = :"pt-BR"
    config.time_zone = "America/Sao_Paulo"
    config.active_record.default_timezone = :utc

    # db/structure.sql preserves RLS policies, exclusion constraints, functions
    # and triggers that the Ruby schema format cannot represent.
    config.active_record.schema_format = :sql

    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
      g.test_framework :rspec
      g.system_tests nil
      g.helper false
      g.assets false
    end

    # Active Storage routes are drawn by the application (see config/routes.rb)
    # so that every download goes through tenant-aware authorization.
    config.active_storage.draw_routes = false
    config.active_storage.variant_processor = :disabled
    config.active_storage.content_types_allowed_inline = %w[image/png image/jpeg image/webp application/pdf]

    config.action_mailer.deliver_later_queue_name = "mailers"
    config.active_job.queue_name_prefix = nil

    # Finished jobs are deleted immediately: job arguments (e.g. Devise e-mail
    # tokens) must not linger in the queue database.
    config.solid_queue.preserve_finished_jobs = false

    # Request IDs are propagated to jobs, outbox events and integration calls.
    config.action_dispatch.request_id_header = "X-Request-Id"

    config.exceptions_app = routes
  end
end

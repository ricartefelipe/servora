# frozen_string_literal: true

Devise.setup do |config|
  require "devise/orm/active_record"

  config.mailer_sender = ENV.fetch("MAILER_FROM", "Servora <nao-responda@servora.local>")
  config.parent_controller = "ApplicationController"

  config.case_insensitive_keys = [:email]
  config.strip_whitespace_keys = [:email]
  config.skip_session_storage = [:http_auth]

  # Responses never reveal whether an e-mail is registered.
  config.paranoid = true

  config.stretches = Rails.env.test? ? 1 : 12
  config.password_length = 12..128
  config.email_regexp = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  config.reconfirmable = true
  config.confirm_within = 3.days

  # Brute force protection: lock after 5 failures, unlock by e-mail or after 30 min.
  config.lock_strategy = :failed_attempts
  config.unlock_keys = [:email]
  config.unlock_strategy = :both
  config.maximum_attempts = 5
  config.unlock_in = 30.minutes
  config.last_attempt_warning = true

  config.reset_password_within = 2.hours
  config.sign_in_after_reset_password = false

  config.timeout_in = 2.hours
  config.expire_all_remember_me_on_sign_out = true
  config.sign_out_via = :delete

  config.navigational_formats = ["*/*", :html, :turbo_stream]
  config.responder.error_status = :unprocessable_content
  config.responder.redirect_status = :see_other
end

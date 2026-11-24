# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAILER_FROM", "Servora <nao-responda@servora.local>") }
  layout "mailer"
end

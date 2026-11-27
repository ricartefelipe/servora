# frozen_string_literal: true

module Servora
  # Public demonstration mode, for an instance that holds nothing but the
  # demonstration data re-seeded every day (bin/db-prepare --seed).
  #
  # It is enabled only by SERVORA_DEMO=1; any other value ("true", "yes", "0",
  # blank) keeps the regular behaviour, so an instance serving real customers
  # cannot switch it on by a loosely written variable. The value is read on
  # every call (a cheap ENV lookup) so the mode follows the process
  # environment and specs can exercise both behaviours.
  #
  # While enabled:
  # - the sign-in page lists the demonstration accounts and their shared
  #   password (shared/_demo_access);
  # - the multi-factor enrollment policy for privileged roles does not apply
  #   (Authentication::MfaRequirement), because the demo proxy blocks the MFA
  #   setup pages.
  module Demo
    SETTINGS = Rails.application.config_for(:demo)

    # Password of the seeded demonstration accounts when SEED_PASSWORD is not
    # set (public, see config/demo.yml). Seeds::PASSWORD
    # (db/seeds/01_organizations_and_people.rb) takes its value from .password,
    # so the seeds and the sign-in page always agree.
    DEFAULT_PASSWORD = SETTINGS.fetch(:default_seed_password)

    # Read-only Mailpit published by the demo proxy. It is the default only in
    # demo mode; SERVORA_DEMO_INBOX_URL overrides it, and setting it blank
    # removes the inbox link from the sign-in page (instance without Mailpit).
    DEFAULT_INBOX_URL = SETTINGS.fetch(:default_inbox_url)

    # Profiles offered on the sign-in page, in presentation order. Every e-mail
    # is a seeded person of organization A (Seeds::PEOPLE); a spec keeps both
    # lists consistent.
    Account = Data.define(:email, :role, :profile, :note)

    ACCOUNTS = [
      Account.new(email: "ana@clima-norte.test", role: "owner", profile: "Proprietária", note: nil),
      Account.new(email: "bruno@clima-norte.test", role: "coordinator", profile: "Coordenador", note: nil),
      Account.new(email: "carla@clima-norte.test", role: "attendant", profile: "Atendente", note: nil),
      Account.new(email: "diego@clima-norte.test", role: "technician", profile: "Técnico", note: "abre a agenda de campo"),
      Account.new(email: "gabriela@clima-norte.test", role: "finance", profile: "Financeiro", note: nil),
      Account.new(email: "heitor@clima-norte.test", role: "auditor", profile: "Auditor", note: "abre a trilha de auditoria")
    ].freeze

    def self.enabled? = ENV.fetch("SERVORA_DEMO", "0") == "1"

    def self.password = ENV.fetch("SEED_PASSWORD", DEFAULT_PASSWORD)

    # Address of the demonstration inbox, or nil when there is none: outside
    # demo mode without an explicit address, or with SERVORA_DEMO_INBOX_URL
    # set blank.
    def self.inbox_url
      return ENV.fetch("SERVORA_DEMO_INBOX_URL", nil).presence if ENV.key?("SERVORA_DEMO_INBOX_URL")

      DEFAULT_INBOX_URL if enabled?
    end

    def self.accounts = ACCOUNTS
  end
end

Rails.application.config.after_initialize do
  if Servora::Demo.enabled?
    Rails.logger.warn("Demo mode enabled (SERVORA_DEMO=1): demonstration accounts are listed on the sign-in page " \
                      "and the MFA enrollment policy is not applied.")
  end
end

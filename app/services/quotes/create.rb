# frozen_string_literal: true

module Quotes
  class Create
    DEFAULT_VALIDITY_DAYS = 15
    DEFAULT_PAYMENT_TERMS = "Pagamento integral na conclusão do serviço."

    def initialize(organization:, actor:, customer:, location:, title:)
      @organization = organization
      @actor = actor
      @customer = customer
      @location = location
      @title = title
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        quote = @organization.quotes.create!(number: Numbering.next!(organization: @organization, scope: "quote"),
          title: @title, customer: @customer, service_location: @location, created_by: @actor, status: "draft")
        version = quote.versions.create!(organization: @organization, version_number: 1, status: "draft",
          valid_until: Time.current.in_time_zone(@organization.zone).to_date + DEFAULT_VALIDITY_DAYS,
          payment_terms: DEFAULT_PAYMENT_TERMS)
        quote.update!(current_version: version)
        History.record!(quote, kind: "created", version:)
        AuditEvent.record!(action: "quote.created", auditable: quote, changes: { number: quote.number, title: @title })
        quote
      end
    end
  end
end

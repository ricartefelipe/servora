# frozen_string_literal: true

module Seeds
  module DemoActivity
    # Quotes of a story: drafting, sending, a new version at the customer's
    # request, the customer's decision and the conversion into a work order.
    # Each action is one use case call made by the member given in the event
    # (`by:`), at the event's instant.
    module QuoteActions
      private

      def quote(key:, customer:, location:, title:, lines: [], free: [])
        client = self.customer(customer)
        quote = Quotes::Create.new(organization:, actor: Current.membership, customer: client,
          location: location(client, location), title:).call
        version = quote.current_version
        lines.each { |sku, quantity| Quotes::AddItem.new(version:, quantity:, catalog_item: catalog(sku)).call }
        free.each do |description, quantity, unit_price|
          Quotes::AddItem.new(version:, quantity:, description:, unit_price:, kind: "part").call
        end
        @ids[:quote][key] = quote.id
      end

      def send_quote(quote:)
        Quotes::SendVersion.new(quote: Quote.find(id_of(:quote, quote))).call
      end

      # A new version of a sent quote, at the customer's request: the lines are
      # added to a copy of the current version, with the request in its notes.
      def revise_quote(quote:, lines:, notes:)
        record = Quote.find(id_of(:quote, quote))
        version = Quotes::NewVersion.new(quote: record).call
        lines.each { |sku, quantity| Quotes::AddItem.new(version:, quantity:, catalog_item: catalog(sku)).call }
        version.reload
        Quotes::UpdateTerms.new(version:, valid_until: version.valid_until, discount: version.discount_amount,
          payment_terms: version.payment_terms, notes:).call
      end

      # decision: "approved" or "rejected" (a rejection needs the reason as note).
      # On the "portal" channel the contact decides alone (no member acting).
      def decide_quote(quote:, contact:, channel:, note: nil, decision: "approved")
        record = Quote.find(id_of(:quote, quote))
        version = record.current_version
        person = contact(contact)
        decide = proc do
          Quotes::Decide.new(quote: record, version_id: version.id, decision:, digest: version.content_digest,
            contact: person, channel:, membership: Current.membership, note:).call
        end
        channel == "portal" ? Current.set(organization:, portal_contact: person, &decide) : decide.call
      end

      def convert_quote(quote:, order:)
        result = WorkOrders::CreateFromQuote.new(quote: Quote.find(id_of(:quote, quote)), actor: Current.membership).call
        @ids[:order][order] = result.work_order.id
      end
    end
  end
end

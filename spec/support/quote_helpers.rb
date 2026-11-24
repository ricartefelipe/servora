# frozen_string_literal: true

# Builds quotes through the real use cases so specs exercise the same rules
# (numbering, snapshots, freezing triggers) as the application.
module QuoteHelpers
  def build_quote_scenario(organization: create(:organization))
    author = create(:membership, :attendant, organization:)
    customer = create(:customer, organization:)
    location = create(:service_location, customer:)
    approver = create(:customer_contact, customer:, can_approve: true, portal_enabled: true)
    { organization:, author:, customer:, location:, approver: }
  end

  def create_quote(scenario, items: [["Manutenção preventiva", "1", "450.00"]])
    as_member(scenario[:author]) do
      quote = Quotes::Create.new(organization: scenario[:organization], actor: scenario[:author], customer: scenario[:customer],
        location: scenario[:location], title: "Manutenção do sistema de climatização").call
      items.each do |description, quantity, price|
        Quotes::AddItem.new(version: quote.current_version, description:, quantity:, unit_price: price, kind: "service").call
      end
      quote.reload
    end
  end

  def send_quote(scenario, quote)
    as_member(scenario[:author]) { Quotes::SendVersion.new(quote:).call }
    in_tenant(scenario[:organization]) { quote.reload.current_version.reload }
  end
end

RSpec.configure do |config|
  config.include QuoteHelpers
end

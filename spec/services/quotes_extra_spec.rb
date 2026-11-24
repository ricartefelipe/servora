# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes do # edge cases of the quote lifecycle
  let(:scenario) { build_quote_scenario }
  let(:organization) { scenario[:organization] }

  it "cancels with a reason and keeps the history" do
    quote = create_quote(scenario)

    expect { as_member(scenario[:author]) { Quotes::Cancel.new(quote:, reason: " ").call } }
      .to raise_error(Quotes::Cancel::NotCancelable, /motivo/)
    as_member(scenario[:author]) { Quotes::Cancel.new(quote:, reason: "Cliente desistiu").call }

    in_tenant(organization) do
      expect(quote.reload.status).to eq("canceled")
      expect(quote.events.first).to have_attributes(kind: "canceled", note: "Cliente desistiu")
    end
    expect { as_member(scenario[:author]) { Quotes::NewVersion.new(quote:).call } }.to raise_error(Quotes::NewVersion::NotAllowed)
  end

  it "does not create a new version while the current one is a draft" do
    quote = create_quote(scenario)

    expect { as_member(scenario[:author]) { Quotes::NewVersion.new(quote:).call } }
      .to raise_error(Quotes::NewVersion::NotAllowed, /rascunho/)
  end

  it "refuses to send a draft with past validity or for an archived customer" do
    quote = create_quote(scenario)

    expect { as_member(scenario[:author]) { Quotes::SendVersion.new(quote:, today: 1.year.from_now.to_date).call } }
      .to raise_error(Quotes::SendVersion::NotSendable, /validade/)
    in_tenant(organization) { scenario[:customer].update!(archived_at: Time.current) }
    expect { as_member(scenario[:author]) { Quotes::SendVersion.new(quote: quote.reload).call } }
      .to raise_error(Quotes::SendVersion::NotSendable, /arquivado/)
  end

  it "refuses edits on sent versions through the use cases" do
    quote = create_quote(scenario)
    version = send_quote(scenario, quote)

    expect do
      as_member(scenario[:author]) { Quotes::AddItem.new(version:, quantity: 1, description: "x", unit_price: "1").call }
    end.to raise_error(Quotes::DraftEditing::NotEditable)
  end

  it "notifies quote managers when the customer decides" do
    quote = create_quote(scenario)
    version = send_quote(scenario, quote)
    in_tenant(organization) do
      Quotes::Decide.new(quote: quote.reload, version_id: version.id, decision: "rejected", digest: version.content_digest,
        contact: scenario[:approver], channel: "portal", note: "Preço acima do orçado").call
    end

    run_dispatcher

    titles = in_tenant(organization) { Notification.where(recipient_membership_id: scenario[:author].id).pluck(:title) }
    expect(titles).to include("Orçamento #{quote.number} recusado")
  end

  it "skips stale quote.sent events after a newer version exists" do
    quote = create_quote(scenario)
    send_quote(scenario, quote)
    as_member(scenario[:author]) { Quotes::NewVersion.new(quote: in_tenant(organization) { quote.reload }).call }

    run_dispatcher

    expect(in_tenant(organization) { PortalAccessGrant.count }).to eq(0)
  end

  it "does not deliver revoked grants and refuses archived contacts at exchange" do
    grant = in_tenant(organization) { Portal::IssueGrant.new(contact: scenario[:approver], purpose: "portal").call }
    in_tenant(organization) { grant.update!(revoked_at: Time.current) }

    expect(Portal::DeliverGrant.new(organization_id: organization.id, grant_id: grant.id).call).to be(false)

    other = in_tenant(organization) { Portal::IssueGrant.new(contact: scenario[:approver], purpose: "portal").call }
    Portal::DeliverGrant.new(organization_id: organization.id, grant_id: other.id).call
    token = ActionMailer::Base.deliveries.last.text_part.body.to_s[%r{/portal/acesso/([\w-]+)}, 1]
    in_tenant(organization) { scenario[:approver].update!(archived_at: Time.current) }

    expect { Portal::ExchangeGrant.new(token:, ip: nil, user_agent: nil).call }
      .to raise_error(Portal::ExchangeGrant::InvalidGrant, /não está disponível/)
    expect { Portal::ExchangeGrant.new(token: "x", ip: nil, user_agent: nil).call }
      .to raise_error(Portal::ExchangeGrant::InvalidGrant, /inválido/)
  end
end

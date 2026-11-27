# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes do
  let(:scenario) { build_quote_scenario }
  let(:organization) { scenario[:organization] }

  describe "drafting" do
    it "creates numbered quotes with a first draft version" do
      quote = create_quote(scenario)

      expect(quote.number).to match(/\AORC-\d{4}-00001\z/)
      expect(in_tenant(organization) { quote.current_version }).to have_attributes(version_number: 1, status: "draft",
        subtotal: BigDecimal("450.00"), total: BigDecimal("450.00"))
    end

    it "copies catalog values so later catalog changes do not affect the quote" do
      item = create(:catalog_item, organization:, name: "Higienização", unit_price: BigDecimal("199.90"))
      quote = create_quote(scenario, items: [])
      as_member(scenario[:author]) do
        described_class::AddItem.new(version: quote.current_version, catalog_item: item, quantity: "2").call
      end

      in_tenant(organization) { item.update!(unit_price: BigDecimal("299.90"), name: "Higienização completa") }

      line = in_tenant(organization) { quote.current_version.items.sole }
      expect(line).to have_attributes(description: "Higienização", unit_price: BigDecimal("199.90"),
        line_total: BigDecimal("399.80"), unit_cost: BigDecimal("90.0"))
    end

    it "applies the global discount and caps it when items are removed" do
      quote = create_quote(scenario, items: [["A", "1", "100.00"], ["B", "1", "50.00"]])
      version = in_tenant(organization) { quote.current_version }
      as_member(scenario[:author]) do
        described_class::UpdateTerms.new(version:, valid_until: 10.days.from_now.to_date, discount: "120",
          payment_terms: "30 dias", notes: "").call
        described_class::RemoveItem.new(item: version.items.find_by!(description: "A")).call
      end

      expect(in_tenant(organization) do
        version.reload
      end).to have_attributes(subtotal: BigDecimal("50"), discount_amount: BigDecimal("50"),
        total: BigDecimal("0"))
    end

    it "refuses discounts larger than the subtotal" do
      quote = create_quote(scenario)

      expect do
        as_member(scenario[:author]) do
          described_class::UpdateTerms.new(version: quote.current_version, valid_until: Date.tomorrow, discount: "999",
            payment_terms: "", notes: "").call
        end
      end.to raise_error(Quotes::UpdateTerms::InvalidTerms)
    end
  end

  describe Quotes::SendVersion do
    it "freezes the content with a snapshot, a digest and an outbox event" do
      version = send_quote(scenario, create_quote(scenario))

      expect(version).to have_attributes(status: "sent", content_digest: Quotes::ContentDigest.call(version.snapshot))
      expect(version.snapshot.dig("totals", "total")).to eq("450.0")
      expect(version.snapshot.to_s).not_to include("unit_cost")
      expect(outbox_events(organization).map(&:event_type)).to include("quote.sent")
    end

    it "refuses to send empty or expired drafts" do
      empty = create_quote(scenario, items: [])

      expect { as_member(scenario[:author]) { described_class.new(quote: empty).call } }
        .to raise_error(Quotes::SendVersion::NotSendable, /ao menos um item/)
    end

    it "never lets the database change a sent version or its items" do
      version = send_quote(scenario, create_quote(scenario))

      in_tenant(organization) do
        expect { ActiveRecord::Base.transaction(requires_new: true) { version.items.first.update_columns(unit_price: 1) } }
          .to raise_error(ActiveRecord::StatementInvalid, /frozen/)
        expect { ActiveRecord::Base.transaction(requires_new: true) { version.update_columns(total: 1, subtotal: 1) } }
          .to raise_error(ActiveRecord::StatementInvalid, /immutable/)
        extra = QuoteItem.new(quote_version: version, organization:, kind: "other", description: "x", unit: "un",
          quantity: 1, unit_price: 1, line_total: 1)
        expect { ActiveRecord::Base.transaction(requires_new: true) { extra.save! } }
          .to raise_error(ActiveRecord::StatementInvalid, /frozen/)
      end
    end
  end

  describe Quotes::Decide do
    let(:quote) { create_quote(scenario) }
    let!(:version) { send_quote(scenario, quote) }

    def decide(**overrides)
      options = { quote: in_tenant(organization) { quote.reload }, version_id: version.id, decision: "approved",
                  digest: version.content_digest, contact: scenario[:approver], channel: "portal", ip: "203.0.113.9",
                  user_agent: "Navegador" }.merge(overrides)
      in_tenant(organization) { described_class.new(**options).call }
    end

    it "records the approved version with evidence and notifies through the outbox" do
      decide

      in_tenant(organization) do
        expect(version.reload).to have_attributes(status: "approved", decided_by_contact_id: scenario[:approver].id,
          decision_channel: "portal", decision_ip: IPAddr.new("203.0.113.9"))
        expect(quote.reload).to have_attributes(status: "approved", approved_version_id: version.id)
        expect(OutboxEvent.pluck(:event_type)).to include("quote.approved")
      end
    end

    it "refuses the approval when the content digest does not match what was shown" do
      expect { decide(digest: "0" * 64) }.to raise_error(described_class::DecisionRefused, /conteúdo foi alterado/)
    end

    it "refuses approving a superseded version after a new version was sent" do
      in_tenant(organization) { as_member(scenario[:author]) { Quotes::NewVersion.new(quote: quote.reload).call } }
      # Superseding iterates in batches: an ordered relation there would only log a warning.
      previous_setting = ActiveRecord.error_on_ignored_order
      ActiveRecord.error_on_ignored_order = true
      begin
        send_quote(scenario, in_tenant(organization) { quote.reload })
      ensure
        ActiveRecord.error_on_ignored_order = previous_setting
      end

      expect { decide }.to raise_error(described_class::DecisionRefused, /não é a vigente/)
      expect(in_tenant(organization) { version.reload.status }).to eq("superseded")
    end

    it "refuses expired versions, unauthorized contacts and a second decision" do
      outsider = create(:customer_contact, customer: create(:customer, organization:), can_approve: true)
      follower = create(:customer_contact, customer: scenario[:customer], can_approve: false)

      expect { decide(now: 30.days.from_now) }.to raise_error(described_class::DecisionRefused, /validade/)
      expect { decide(contact: outsider) }.to raise_error(described_class::DecisionRefused, /não pode aprovar/)
      expect { decide(contact: follower) }.to raise_error(described_class::DecisionRefused, /não pode aprovar/)
      decide
      expect do
        decide(decision: "rejected", note: "mudei de ideia")
      end.to raise_error(described_class::DecisionRefused, /não está aguardando/)
    end

    it "requires a reason to reject and a registering member for internal channels" do
      expect { decide(decision: "rejected") }.to raise_error(described_class::DecisionRefused, /motivo/)
      expect { decide(channel: "phone") }.to raise_error(described_class::DecisionRefused, /responsável/)
    end
  end

  describe Quotes::NewVersion do
    it "copies the items into a new draft and keeps the sent version untouched" do
      quote = create_quote(scenario)
      sent = send_quote(scenario, quote)

      draft = as_member(scenario[:author]) { described_class.new(quote: in_tenant(organization) { quote.reload }).call }

      in_tenant(organization) do
        expect(draft).to have_attributes(version_number: 2, status: "draft", total: sent.total)
        expect(draft.items.map(&:description)).to eq(sent.items.map(&:description))
        expect(quote.reload.status).to eq("draft")
      end
    end
  end

  describe Quotes::ExpireDue do
    it "expires sent versions past their validity" do
      quote = create_quote(scenario)
      send_quote(scenario, quote)

      expired = in_tenant(organization) { described_class.new(organization:, today: 60.days.from_now.to_date).call }

      expect(expired).to eq(1)
      expect(in_tenant(organization) { quote.reload.status }).to eq("expired")
    end
  end
end

# frozen_string_literal: true

RSpec.describe Audit::Labels do
  describe ".action" do
    it "names the area and what happened in pt-BR" do
      expect(described_class.action("work_order.completed")).to eq("Ordem de serviço · concluída")
      expect(described_class.action("stock.minimum_changed")).to eq("Estoque · mínimo alterado")
      expect(described_class.action("service_invoice.authorized")).to eq("Nota fiscal de serviço · autorizada")
    end

    it "humanizes unknown keys instead of raising" do
      expect(described_class.action("legacy_thing.got_synced")).to eq("Legacy thing · got synced")
      expect(described_class.action("work_order.teleported")).to eq("Ordem de serviço · teleported")
      expect(described_class.action("orphan")).to eq("Orphan")
      expect(described_class.action(nil)).to eq("—")
      expect(described_class.action("")).to eq("—")
    end

    it "tells known keys apart" do
      expect(described_class.known?("quote.approved")).to be(true)
      expect(described_class.known?("quote.teleported")).to be(false)
      expect(described_class.known?(nil)).to be(false)
    end
  end

  describe ".grouped" do
    it "groups the keys by area for the filter, keeping the raw keys as values" do
      grouped = described_class.grouped(%w[work_order.completed stock.adjusted work_order.created stock.adjusted])

      expect(grouped).to eq(
        [
          ["Estoque", [["Estoque · ajuste registrado", "stock.adjusted"]]],
          ["Ordem de serviço", [["Ordem de serviço · concluída", "work_order.completed"],
                                ["Ordem de serviço · criada", "work_order.created"]]]
        ]
      )
    end
  end

  describe ".hidden?" do
    it "hides plumbing, unresolvable foreign keys and credential-like fields" do
      hidden = %w[id organization_id created_at updated_at lock_version visit_id contract_id
                  webhook_token_digest api_key access_token password otp_secret]

      expect(hidden.reject { |field| described_class.hidden?(field, references: %w[membership_id]) }).to be_empty
    end

    it "keeps business fields and the foreign keys that can be resolved to a name" do
      shown = %w[name reason amount membership_id]

      expect(shown.select { |field| described_class.hidden?(field, references: %w[membership_id]) }).to be_empty
    end
  end

  it "labels from/to changesets by the subject of the action" do
    expect(described_class.from_to_label("contract.suspended")).to eq("Situação")
    expect(described_class.from_to_label("stock.minimum_changed")).to eq("Estoque mínimo")
    expect(described_class.from_to_label("report.exported")).to eq("Período")
    expect(described_class.from_to_label("something.else")).to eq("Valor")
  end

  it "names fields in pt-BR and humanizes the rest" do
    expect(described_class.field("reason")).to eq("Motivo")
    expect(described_class.field("brand_new_field")).to eq("Brand new field")
  end
end

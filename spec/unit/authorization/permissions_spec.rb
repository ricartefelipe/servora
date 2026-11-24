# frozen_string_literal: true

RSpec.describe Authorization::Permissions do
  describe ".granted?" do
    it "grants every permission to the owner" do
      expect(described_class::ALL).to all(satisfy { |permission| described_class.granted?("owner", permission) })
    end

    it "keeps the platform subscription exclusive to the owner" do
      roles = described_class::ROLES.select { |role| described_class.granted?(role, :subscription_manage) }

      expect(roles).to eq(%w[owner])
    end

    it "does not expose internal costs to operational roles by default" do
      %w[coordinator attendant technician].each do |role|
        expect(described_class.granted?(role, :costs_view)).to be(false), "#{role} should not see costs"
      end
    end

    it "limits technicians to field execution" do
      expect(described_class.for("technician")).to contain_exactly(
        :equipment_view, :catalog_view, :work_orders_execute, :schedule_view, :inventory_view
      )
    end

    it "keeps the auditor read-only" do
      mutating = described_class.for("auditor").select { |permission| permission.to_s.end_with?("_manage", "_adjust", "_refund") }

      expect(mutating).to be_empty
      expect(described_class.granted?("auditor", :audit_view)).to be(true)
    end

    it "denies everything to unknown roles" do
      expect(described_class.granted?("visitor", :customers_view)).to be(false)
    end

    it "rejects permissions that do not exist" do
      expect { described_class.granted?("owner", :launch_rockets) }.to raise_error(ArgumentError, /unknown permission/)
    end
  end

  describe ".privileged?" do
    it "flags roles that must use multi-factor authentication" do
      expect(described_class::ROLES.select { |role| described_class.privileged?(role) }).to eq(%w[owner admin finance])
    end
  end
end

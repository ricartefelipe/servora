# frozen_string_literal: true

require "rails_helper"

RSpec.describe Servora::Demo do
  # Literal values of db/seeds/01_organizations_and_people.rb, read statically
  # so the seed itself (which writes to the database) is not executed.
  def seed_constant(name)
    pending = [Prism.parse_file(Rails.root.join("db/seeds/01_organizations_and_people.rb").to_s).value]
    while (node = pending.shift)
      return node.value if node.is_a?(Prism::ConstantWriteNode) && node.name == name

      pending.concat(node.compact_child_nodes)
    end
    raise "#{name} not found in the seeds"
  end

  # Strings, arrays and hashes of them; `nil` literals (and anything else) become nil.
  def literal(node)
    case node
    when Prism::StringNode then node.unescaped
    when Prism::ArrayNode then node.elements.map { |element| literal(element) }
    when Prism::HashNode then node.elements.to_h { |pair| [literal(pair.key), literal(pair.value)] }
    when Prism::CallNode then literal(node.receiver) # `.freeze`
    end
  end

  describe ".enabled?" do
    it "is on only for SERVORA_DEMO=1" do
      { "1" => true, "0" => false, "true" => false, "yes" => false, "" => false, nil => false }.each do |value, enabled|
        with_environment("SERVORA_DEMO" => value) { expect(described_class.enabled?).to be(enabled), value.inspect }
      end
    end
  end

  describe ".password" do
    it "reads SEED_PASSWORD, with the demonstration default" do
      with_environment("SEED_PASSWORD" => nil) { expect(described_class.password).to eq(described_class::DEFAULT_PASSWORD) }
      with_environment("SEED_PASSWORD" => "senha-publica") { expect(described_class.password).to eq("senha-publica") }
    end
  end

  describe ".inbox_url" do
    it "defaults to the inbox published by the demo proxy in demo mode", :demo_mode do
      with_environment("SERVORA_DEMO_INBOX_URL" => nil) { expect(described_class.inbox_url).to eq("/caixa-de-entrada") }
      with_environment("SERVORA_DEMO_INBOX_URL" => "http://localhost:58025") do
        expect(described_class.inbox_url).to eq("http://localhost:58025")
      end
    end

    it "is absent when set blank, so the sign-in page offers no inbox link", :demo_mode do
      with_environment("SERVORA_DEMO_INBOX_URL" => "") { expect(described_class.inbox_url).to be_nil }
    end

    it "has no default outside demo mode", demo_mode: false do
      with_environment("SERVORA_DEMO_INBOX_URL" => nil) { expect(described_class.inbox_url).to be_nil }
    end
  end

  describe "consistency with the seeds" do
    it "gives the seeded people the password shown on the sign-in page" do
      call = seed_constant(:PASSWORD)

      expect(call).to be_a(Prism::CallNode)
      expect([call.receiver.slice, call.name, call.arguments]).to eq(["Servora::Demo", :password, nil])
    end

    it "offers only seeded people of organization A, with their seeded roles" do
      seeded = literal(seed_constant(:PEOPLE)).fetch("a").to_h { |_name, email, role, _cost| [email, role] }

      described_class.accounts.each do |account|
        expect(seeded[account.email]).to eq(account.role), account.email
      end
    end
  end
end

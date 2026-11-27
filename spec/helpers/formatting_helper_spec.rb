# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormattingHelper do
  describe "#format_phone" do
    it "shows Brazilian numbers with the mask and leaves the value untouched" do
      stored = "11987412035"

      expect(helper.format_phone(stored)).to eq("(11) 98741-2035")
      expect(helper.format_phone("+55 (11) 3333-4444")).to eq("(11) 3333-4444")
      expect(stored).to eq("11987412035")
    end

    it "returns nil for blank values so views can fall back to a dash" do
      expect(helper.format_phone(nil)).to be_nil
      expect(helper.format_phone("  ")).to be_nil
    end

    it "keeps numbers it does not recognize as typed" do
      expect(helper.format_phone("+44 20 7946 0958")).to eq("+44 20 7946 0958")
    end
  end

  describe "#breakable_code" do
    it "allows line breaks only after the hyphens of a code" do
      expect(helper.breakable_code("OS-2026-00042")).to eq("OS-<wbr>2026-<wbr>00042")
      expect(helper.breakable_code("<b>")).to eq("&lt;b&gt;")
    end
  end
end

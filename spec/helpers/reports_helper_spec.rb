# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReportsHelper do
  it "shows percentages in the pt-BR format" do
    expect(helper.report_value(Reports::Percent.of(2, 3))).to eq("66,7%")
    expect(helper.report_value(Reports::Percent.of(3, 3))).to eq("100,0%")
  end

  it "formats margins and missing percentages the same way" do
    expect(helper.percentage(BigDecimal("56.2"))).to eq("56,2%")
    expect(helper.percentage(BigDecimal("-50"))).to eq("-50,0%")
    expect(helper.percentage(nil)).to eq("—")
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkOrderStatusHelper do
  def badge_for(status) = Nokogiri::HTML.fragment(helper.work_order_status_badge(status)).at_css(".sv-badge")

  it "gives neighbouring work order states distinct hues" do
    tones = WorkOrderStatusHelper::TONES

    expect(tones.values_at("approved", "scheduled")).to eq(%i[info indigo])
    expect(tones.values_at("in_progress", "waiting_parts", "waiting_customer")).to eq(%i[ember warning warning])
  end

  it "always labels the state and marks the waiting states with a pause glyph instead of the dot" do
    waiting = badge_for("waiting_parts")
    running = badge_for("in_progress")

    expect(waiting.text).to eq("Aguardando peças")
    expect(waiting.at_css("svg.text-amber-600")).to be_present
    expect(waiting.at_css("span.rounded-full")).to be_nil
    expect(running.text).to eq("Em execução")
    expect(running.at_css("span.rounded-full.bg-ember-500")).to be_present
    expect(running.at_css("svg")).to be_nil
  end

  it "marks a past deadline as danger with the alert icon and one at risk as warning with a clock" do
    overdue = Nokogiri::HTML.fragment(helper.work_order_deadline_badge(:overdue)).at_css(".sv-badge")
    at_risk = Nokogiri::HTML.fragment(helper.work_order_deadline_badge(:at_risk)).at_css(".sv-badge")

    expect([overdue.text, at_risk.text]).to eq(["Prazo estourado", "Prazo em risco"])
    expect(overdue.at_css("svg.text-rose-600")).to be_present
    expect(at_risk.at_css("svg.text-amber-600")).to be_present
    expect(helper.work_order_deadline_badge(nil)).to be_nil
  end

  it "names the list filters in reading order, ignoring a blank search" do
    expect(helper.work_order_filter_summary(status: "waiting_parts", deadline: "em_risco", term: "  split  gelado "))
      .to eq(["Situação: Aguardando peças", "Prazo em risco", "Busca: “split gelado”"])
    expect(helper.work_order_filter_summary(status: nil, deadline: nil, term: " ")).to be_empty
  end

  it "shows the search term exactly as the query uses it, truncated to its limit" do
    long_term = "#{"compressor " * 10}fim"
    searched = WorkOrders::SearchQuery.normalize_term(long_term)

    expect(searched.length).to eq(WorkOrders::SearchQuery::TERM_MAX_LENGTH)
    expect(helper.work_order_filter_summary(status: nil, deadline: nil, term: long_term)).to eq(["Busca: “#{searched}”"])
    expect(helper.work_order_filter_summary(status: nil, deadline: nil, term: long_term).sole).not_to include("fim")
  end

  it "accepts the label shown to customers" do
    expect(Nokogiri::HTML.fragment(helper.work_order_status_badge("open", "Em análise")).text).to eq("Em análise")
  end
end

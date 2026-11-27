# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Agenda now marker" do
  let(:scenario) { build_work_order_scenario }

  # Diego works 08:00–18:00, so the day timeline shows those hours.
  before { create_technician(scenario[:organization], name: "Diego Alves") }

  def agenda_at(time, **params)
    travel_to(time) do
      sign_in_as(scenario[:coordinator])
      get agenda_index_path(**params)
    end
    response.parsed_body
  end

  def epoch_ms(time) = (time.to_f * 1000).round.to_s

  it "gives the controller the window, the server clock and the organization's zone" do
    timeline = agenda_at(tuesday_at(10, 37)).at_css("[data-controller='now-line']")

    expect(timeline["aria-label"]).to eq("Linha do tempo do dia")
    expect(timeline["data-now-line-start-value"]).to eq(epoch_ms(tuesday_at(8)))
    expect(timeline["data-now-line-end-value"]).to eq(epoch_ms(tuesday_at(18)))
    expect(timeline["data-now-line-server-now-value"]).to eq(epoch_ms(tuesday_at(10, 37)))
    expect(timeline["data-now-line-time-zone-value"]).to eq("America/Sao_Paulo")
    expect(timeline["data-now-line-utc-offset-value"]).to eq("-10800")
  end

  it "places the line and the pill at the exact current minute" do
    page = agenda_at(tuesday_at(10, 37))

    # 157 minutes into the 600-minute window (960 units): no snapping to the 15-minute grid.
    line = page.at_css("[data-now-line-target='line']")
    expect([line["x1"], line["x2"]]).to eq(%w[251.20 251.20])
    expect(page.at_css("[data-now-line-target='pill']")["x"]).to eq("26.167%")
    expect(page.at_css("[data-now-line-target='time']").text).to eq("10:37")
    expect(page.css("[data-now-line-target~='marker']")).to all(satisfy { |node| !node.key?("hidden") })
  end

  it "keeps a quiet screen-reader text with the current time" do
    label = agenda_at(tuesday_at(10, 37)).at_css("[data-now-line-target~='label']")

    expect(label.text).to eq("Agora, 10:37")
    expect(label["class"]).to include("sr-only")
    expect(label["aria-live"]).to eq("off")
  end

  it "keeps the pill inside the timeline at the end of the day" do
    page = agenda_at(tuesday_at(17, 55))

    expect(page.at_css("[data-now-line-target='pillBody']")["transform"]).to eq("translate(-22 0)")
  end

  it "renders the marker hidden outside the hours shown so the controller can reveal it" do
    page = agenda_at(tuesday_at(5, 30))

    markers = page.css("[data-now-line-target~='marker']")
    expect(markers.size).to eq(3)
    expect(markers).to all(satisfy { |node| node.key?("hidden") })
  end

  it "has no marker on a day other than today" do
    page = agenda_at(tuesday_at(10), data: "2026-12-02")

    expect(page.at_css("[data-controller='now-line']")).to be_nil
    expect(page.text).not_to include("Agora,")
  end

  it "keeps the marker free of inline styles" do
    page = agenda_at(tuesday_at(10))

    expect(page.at_css("[data-controller='now-line']").css("[style]")).to be_empty
  end

  context "when the organization is in another time zone" do
    let(:scenario) { build_work_order_scenario(organization: create(:organization, time_zone: "America/Manaus")) }

    it "measures the window and formats the time in the organization's zone" do
      page = agenda_at(tuesday_at(10)) # 09:00 in Manaus, one hour into Diego's 08:00–18:00 there

      timeline = page.at_css("[data-controller='now-line']")
      expect(timeline["data-now-line-time-zone-value"]).to eq("America/Manaus")
      expect(timeline["data-now-line-start-value"]).to eq(epoch_ms(tuesday_at(9)))
      expect(page.at_css("[data-now-line-target='time']").text).to eq("09:00")
      expect(page.at_css("[data-now-line-target='line']")["x1"]).to eq("96.00")
    end
  end
end

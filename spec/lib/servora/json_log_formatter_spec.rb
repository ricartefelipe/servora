# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/servora/json_log_formatter")

RSpec.describe Servora::JsonLogFormatter do
  let(:time) { Time.utc(2026, 11, 24, 12, 0, 0) }

  def formatted(message) = JSON.parse(described_class.new.call("INFO", time, nil, message))

  it "keeps structured lines and adds time and level" do
    expect(formatted('{"event":"http.request","status":200}')).to eq(
      "time" => "2026-11-24T12:00:00.000Z", "level" => "INFO", "event" => "http.request", "status" => 200
    )
  end

  it "wraps plain or malformed messages" do
    expect(formatted("Started GET \"/painel\"")).to include("message" => "Started GET \"/painel\"")
    expect(formatted("{incompleto")).to include("message" => "{incompleto")
    expect(formatted(%w[a b])).to include("message" => '["a", "b"]')
  end
end

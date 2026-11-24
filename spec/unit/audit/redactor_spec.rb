# frozen_string_literal: true

RSpec.describe Audit::Redactor do
  it "masks sensitive keys at any depth" do
    result = described_class.redact(
      "email" => "ana@servora.test",
      "password" => "segredo",
      "integration" => { "api_key" => "abc", "nested" => { "access_token" => "xyz", "kept" => 1 } },
      "otp_secret" => "BASE32"
    )

    expect(result).to eq(
      "email" => "ana@servora.test",
      "password" => "[FILTRADO]",
      "integration" => { "api_key" => "[FILTRADO]", "nested" => { "access_token" => "[FILTRADO]", "kept" => 1 } },
      "otp_secret" => "[FILTRADO]"
    )
  end

  it "truncates long strings so payloads are not stored in full" do
    result = described_class.redact("note" => "a" * 2_000)

    expect(result["note"].length).to eq(described_class::MAX_STRING + 1)
  end

  it "keeps the marker that records a replaced credential, which holds no secret" do
    expect(described_class.redact("api_key" => "[ALTERADA]", "token" => "abc"))
      .to eq("api_key" => "[ALTERADA]", "token" => "[FILTRADO]")
  end

  it "serializes decimals without float conversion" do
    expect(described_class.redact("amount" => BigDecimal("10.10"))).to eq("amount" => "10.1")
  end

  it "limits nesting depth and array size" do
    deep = { "a" => { "b" => { "c" => { "d" => { "e" => { "f" => { "g" => 1 } } } } } } }
    list = { "items" => (1..80).to_a }

    expect(described_class.redact(deep).dig("a", "b", "c", "d", "e", "f")).to eq("[...]")
    expect(described_class.redact(list)["items"].size).to eq(50)
  end
end

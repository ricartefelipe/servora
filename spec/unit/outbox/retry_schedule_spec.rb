# frozen_string_literal: true

RSpec.describe Outbox::RetrySchedule do
  it "doubles the delay per attempt with a bounded deterministic jitter" do
    delays = (1..4).map { |attempt| described_class.delay_for(attempt:, key: "abc") }

    expect(delays).to eq([15, 30, 60, 120].map { |base| base + (base * ("abc".sum % 10) / 100) })
  end

  it "caps the delay at one hour plus jitter" do
    expect(described_class.delay_for(attempt: 30, key: "x")).to be_between(3_600, 3_960)
  end

  it "rejects non-positive attempts" do
    expect { described_class.delay_for(attempt: 0, key: "x") }.to raise_error(ArgumentError)
  end

  it "knows when attempts are exhausted" do
    expect(described_class.exhausted?(attempt: 8, max_attempts: 8)).to be(true)
    expect(described_class.exhausted?(attempt: 7, max_attempts: 8)).to be(false)
  end
end

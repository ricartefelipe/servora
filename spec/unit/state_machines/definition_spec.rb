# frozen_string_literal: true

RSpec.describe StateMachines::Definition do
  subject(:machine) { described_class.new(open: %i[closed], closed: %i[open archived]) }

  it "lists states and targets" do
    expect(machine.states).to contain_exactly("open", "closed", "archived")
    expect(machine.targets(:closed)).to eq(%w[open archived])
    expect(machine.targets(:unknown)).to eq([])
  end

  it "asserts transitions and exposes their ends" do
    expect(machine.assert!(:open, :closed)).to eq("closed")
    error = begin
      machine.assert!(:archived, :open)
    rescue described_class::InvalidTransition => e
      e
    end
    expect([error.from, error.to]).to eq(%i[archived open])
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkOrders::BulkChangeStatus do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }

  def run(ids, to: "scheduled", authorize: ->(_work_order) { true }, reason: nil)
    as_member(scenario[:coordinator]) do
      described_class.new(scope: WorkOrder.where(organization_id: organization.id), ids:, to:, reason:,
        actor: scenario[:coordinator], authorize:).call
    end
  end

  it "refuses orders the authorization callable rejects and still changes the others" do
    allowed = open_work_order(scenario)
    refused = open_work_order(scenario, title: "Sem permissão")

    result = run([allowed.id, refused.id], authorize: ->(work_order) { work_order.id == allowed.id })

    expect(result.updated).to eq([allowed])
    expect(result.failed.map { |failure| [failure.work_order.number, failure.reason] }).to eq([[refused.number, "sem permissão"]])
    expect(in_tenant(organization) { [allowed.reload.status, refused.reload.status] }).to eq(%w[scheduled approved])
  end

  it "rolls back only the order whose change fails inside its savepoint" do
    first = open_work_order(scenario)
    failing = open_work_order(scenario, title: "Falha")
    # Fails after the status row was written, so only the savepoint can undo it.
    allow(Outbox::Publisher).to receive(:publish!).and_wrap_original do |publish, **arguments|
      raise ActiveRecord::RecordInvalid if arguments[:aggregate].id == failing.id

      publish.call(**arguments)
    end

    result = run([first.id, failing.id])

    expect(result.updated.map(&:id)).to eq([first.id])
    expect(result.failed.map(&:reason)).to eq(["não foi possível alterar"])
    expect(in_tenant(organization) { [first.reload.status, failing.reload.status] }).to eq(%w[scheduled approved])
    expect(in_tenant(organization) { WorkOrderTransition.exists?(work_order_id: failing.id, to_status: "scheduled") })
      .to be(false)
  end

  it "ignores malformed and duplicated ids" do
    work_order = open_work_order(scenario)

    result = run([work_order.id, work_order.id, "1 OR 1=1", nil])

    expect(result.updated.map(&:id)).to eq([work_order.id])
    expect(result.failed).to be_empty
  end
end

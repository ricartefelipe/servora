# frozen_string_literal: true

module OutboxHelpers
  def run_dispatcher(worker_id: "spec-worker")
    Outbox::Dispatcher.new(worker_id:).run_once
  end

  def outbox_events(organization)
    in_tenant(organization) { OutboxEvent.order(:created_at).to_a }
  end
end

RSpec.configure do |config|
  config.include OutboxHelpers
end

# frozen_string_literal: true

require "rails_helper"

# Runs with real commits: claiming, leases and SKIP LOCKED only behave as in
# production when every step commits.
RSpec.describe Outbox::Dispatcher, :committed do
  include ActiveJob::TestHelper

  let(:organization) { create(:organization) }
  let(:owner) { create(:membership, :owner, organization:) }

  def issue_invitation(email = "novo@servora.test")
    as_member(owner) { Invitations::Issue.new(inviter: owner, email:, role: "technician").call }
  end

  it "delivers the business event and is idempotent on repeated runs" do
    invitation = issue_invitation

    first = run_dispatcher
    second = run_dispatcher

    expect(first.to_h).to include(claimed: 1, processed: 1)
    expect(second.claimed).to eq(0)
    expect(Invitations::DeliveryJob).to have_been_enqueued.with(organization.id, invitation.id).exactly(:once)
    expect(outbox_events(organization).sole).to have_attributes(status: "processed", attempts: 1, locked_by: nil)
  end

  it "recovers an event whose post-commit enqueue failed (failure after commit, before enqueue)" do
    allow(Outbox::DispatchJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "fila indisponível")

    invitation = issue_invitation

    expect(Outbox::DispatchJob).to have_received(:perform_later) # rubocop:disable RSpecRails/ReceivePerformLater
    expect(outbox_events(organization).sole.status).to eq("pending")
    run_dispatcher
    expect(Invitations::DeliveryJob).to have_been_enqueued.with(organization.id, invitation.id)
  end

  it "reclaims an event when the worker dies mid-processing (lease expiry)" do
    issue_invitation
    crashed = described_class.new(worker_id: "worker-a")
    event_id, organization_id = crashed.claim.sole
    in_tenant(organization) { OutboxEvent.where(id: event_id).update_all(locked_until: 1.second.ago) }

    stats = run_dispatcher(worker_id: "worker-b")
    late = Outbox::Processing.new(event_id:, organization_id:, worker_id: "worker-a").call

    expect(stats.processed).to eq(1)
    expect(late).to eq(:skipped)
    expect(outbox_events(organization).sole).to have_attributes(status: "processed", attempts: 2)
    expect(Invitations::DeliveryJob).to have_been_enqueued.exactly(:once)
  end

  it "creates the in-app notification only once when an event is processed twice" do
    token = Invitation.generate_token
    invitee = create(:user, email: "entra@servora.test")
    create(:invitation, organization:, invited_by: owner, email: invitee.email, token:)
    Invitations::Accept.new(token:, user: invitee).call
    run_dispatcher # first run also handles invitation.issued-free event set
    event = outbox_events(organization).find { |e| e.event_type == "invitation.accepted" }
    in_tenant(organization) { OutboxEvent.where(id: event.id).update_all(status: "pending", available_at: 1.second.ago) }

    run_dispatcher

    notifications = in_tenant(organization) { Notification.where(recipient_membership_id: owner.id).to_a }
    expect(notifications.map(&:kind)).to eq(["invitation.accepted"])
    expect(notifications.sole.title).to include(invitee.name)
  end

  it "retries transient failures with backoff and records the history" do
    issue_invitation
    allow(Invitations::DeliveryJob).to receive(:perform_later).and_raise(Servora::TransientError, "SMTP indisponível")

    stats = run_dispatcher

    event = outbox_events(organization).sole
    failure = in_tenant(organization) { event.failures.sole }
    expect(stats.retried).to eq(1)
    expect(event).to have_attributes(status: "pending", attempts: 1, locked_by: nil)
    expect(event.available_at).to be > 10.seconds.from_now
    expect(failure).to have_attributes(attempt: 1, transient: true, error_class: "Servora::TransientError")
  end

  it "sets permanent failures aside without retrying" do
    issue_invitation
    in_tenant(organization) { OutboxEvent.update_all(event_type: "evento.desconhecido") }

    stats = run_dispatcher

    expect(stats.dead).to eq(1)
    expect(outbox_events(organization).sole).to have_attributes(status: "dead")
    expect(outbox_events(organization).sole.last_error).to include("Outbox::Registry::UnknownEvent")
  end

  it "stops retrying after the maximum number of attempts" do
    issue_invitation
    in_tenant(organization) { OutboxEvent.update_all(max_attempts: 2) }
    allow(Invitations::DeliveryJob).to receive(:perform_later).and_raise(Servora::TransientError)

    run_dispatcher
    in_tenant(organization) { OutboxEvent.update_all(available_at: 1.second.ago) }
    run_dispatcher

    event = outbox_events(organization).sole
    expect(event).to have_attributes(status: "dead", attempts: 2)
    expect(in_tenant(organization) { event.failures.count }).to eq(2)
  end

  it "lets concurrent dispatchers claim disjoint events" do
    5.times { |index| issue_invitation("convite-concorrente#{index}@servora.test") }

    claims = ConcurrencyHelpers.run_in_parallel(2) do |index|
      described_class.new(worker_id: "worker-#{index}", batch_size: 5).claim.map(&:first)
    end

    expect(claims.flatten.size).to eq(5)
    expect(claims.flatten.uniq.size).to eq(5)
  end

  it "never exposes events of other organizations to the application role without the claim function" do
    issue_invitation

    expect(OutboxEvent.count).to eq(0)
  end
end

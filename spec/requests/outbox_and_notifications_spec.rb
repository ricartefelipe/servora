# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Outbox and notifications" do
  let(:organization) { create(:organization) }
  let(:owner) { create(:membership, :owner, organization:) }

  def dead_event
    invitation = create(:invitation, organization:, invited_by: owner)
    in_tenant(organization) do
      OutboxEvent.create!(organization:, event_type: "invitation.issued", aggregate_type: "Invitation",
        aggregate_id: invitation.id, status: "dead", attempts: 8, last_error: "Servora::PermanentError: falhou")
    end
  end

  it "lists events that need attention for administrators" do
    event = dead_event
    sign_in_as(owner)

    get outbox_events_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("invitation.issued", "Falha definitiva")
    get outbox_event_path(event)
    expect(response.body).to include("Reprocessar")
  end

  it "reprocesses a dead event and audits the action" do
    event = dead_event
    sign_in_as(owner)

    patch reprocess_outbox_event_path(event)

    in_tenant(organization) do
      expect(event.reload).to have_attributes(status: "pending", attempts: 0)
      expect(AuditEvent.where(action: "outbox.reprocessed", auditable_id: event.id)).to exist
    end
  end

  it "hides events from roles without permission (scoped lookup answers 404)" do
    event = dead_event
    sign_in_as(create(:membership, :coordinator, organization:))

    patch reprocess_outbox_event_path(event)

    expect(response).to have_http_status(:not_found)
    expect(in_tenant(organization) { event.reload.status }).to eq("dead")
  end

  it "shows each member only their own notifications and marks them as read" do
    other = create(:membership, :technician, organization:)
    mine, theirs = in_tenant(organization) do
      [Notification.create!(organization:, recipient: owner, kind: "x", title: "Para mim",
        outbox_event_id: SecureRandom.uuid, path: "/painel"),
       Notification.create!(organization:, recipient: other, kind: "x", title: "Para outra pessoa",
         outbox_event_id: SecureRandom.uuid)]
    end
    sign_in_as(owner)

    get notifications_path
    expect(response.body).to include("Para mim")
    expect(response.body).not_to include("Para outra pessoa")

    patch notification_path(mine)
    expect(response).to redirect_to("/painel")
    expect(in_tenant(organization) { mine.reload.read? }).to be(true)

    patch notification_path(theirs)
    expect(response).to have_http_status(:not_found)
  end
end

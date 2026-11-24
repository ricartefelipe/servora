# frozen_string_literal: true

module Outbox
  # Event type → handlers. Every handler must be idempotent: an event can be
  # processed more than once (lease expiry, crash before acknowledgement).
  module Registry
    HANDLERS = {
      "invitation.issued" => ["Invitations::Handlers::DeliverInvitation"],
      "invitation.accepted" => ["Notifications::Handlers::InvitationAccepted"],
      "quote.sent" => ["Quotes::Handlers::NotifyApprovers"],
      "quote.approved" => ["Notifications::Handlers::QuoteDecided", "Webhooks::Handlers::Fanout"],
      "quote.rejected" => ["Notifications::Handlers::QuoteDecided", "Webhooks::Handlers::Fanout"],
      "work_order.created" => ["Webhooks::Handlers::Fanout"],
      "work_order.requested" => ["Notifications::Handlers::PortalRequest"],
      "work_order.completed" => ["Inventory::Handlers::ReleaseWorkOrderReservations", "Webhooks::Handlers::Fanout"],
      "work_order.canceled" => ["Scheduling::Handlers::ReleaseCanceledWorkOrder", "Inventory::Handlers::ReleaseWorkOrderReservations",
                                "Webhooks::Handlers::Fanout"],
      "work_order.reopened" => [],
      "work_order.status_changed" => [],
      "visit.scheduled" => ["Notifications::Handlers::VisitScheduled"],
      "visit.started" => [],
      "visit.finished" => [],
      "payment_charge.requested" => ["Payments::Handlers::SubmitCharge"],
      "payment_charge.canceled" => ["Payments::Handlers::CancelRemoteCharge"],
      "receivable.settled" => ["Invoices::Handlers::AutoIssue"],
      "service_invoice.requested" => ["Invoices::Handlers::Submit"],
      "service_invoice.cancel_requested" => ["Invoices::Handlers::CancelRemote"],
      "payment_refund.requested" => ["Payments::Handlers::SubmitRefund"],
      "sla.warning" => ["Notifications::Handlers::SlaAlert"],
      "sla.breached" => ["Notifications::Handlers::SlaAlert"],
      "inbound_webhook.received" => ["Webhooks::Handlers::ProcessInbound"]
    }.freeze

    class UnknownEvent < Servora::PermanentError; end

    module_function

    def handlers_for(event_type)
      names = HANDLERS.fetch(event_type) { raise UnknownEvent, "Nenhum handler registrado para #{event_type}" }
      names.map(&:constantize)
    end
  end
end

# frozen_string_literal: true

module Subscriptions
  # Technician seats: active technicians plus pending technician invitations
  # may not exceed the contracted seats. Organizations without a subscription
  # record (created before subscriptions existed) are not limited.
  module Seats
    module_function

    def in_use(organization_id)
      Membership.where(organization_id:, role: "technician", status: "active").count +
        Invitation.pending.where(organization_id:, role: "technician").where("expires_at > ?", Time.current).count
    end

    def ensure_available!(organization_id, adding: 1)
      subscription = Subscription.includes(:plan).find_by(organization_id:)
      return unless subscription
      return if in_use(organization_id) + adding <= subscription.technician_seats

      raise Servora::RuleViolation, "Todas as #{subscription.technician_seats} vagas de técnico do plano estão em uso. " \
                                    "Amplie a assinatura para incluir mais técnicos."
    end
  end
end

# frozen_string_literal: true

module Visits
  # Visit state change validated by Visits::States and recorded in
  # visit_transitions. Caller holds the visit row lock.
  module Transition
    class InvalidTransition < Servora::RuleViolation; end

    module_function

    def apply!(visit, to:, actor:, reason: nil, **attributes)
      unless Visits::States.allowed?(visit.status, to)
        raise InvalidTransition, "A visita está #{visit.status_label.downcase} e não pode ir para #{Visits::LABELS.fetch(to.to_s).downcase}."
      end

      from = visit.status
      visit.update!(attributes.merge(status: to))
      visit.transitions.create!(organization_id: visit.organization_id, from_status: from, to_status: to.to_s, reason:,
        actor_membership_id: actor&.id, actor_label: actor&.user&.name || Current.actor_label)
      visit
    end

    def release_allocations!(visit, at: Time.current)
      visit.allocations.active.update_all(status: "released", released_at: at, updated_at: at) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end

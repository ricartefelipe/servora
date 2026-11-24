# frozen_string_literal: true

module Scheduling
  # Explains a rejected reservation by listing the conflicting allocations.
  module ConflictDetector
    module_function

    def message(membership_ids, interval)
      conflicts = TechnicianAllocation.active.overlapping(interval).where(membership_id: membership_ids)
        .includes(membership: :user, visit: :work_order).to_a
      return "Conflito de agenda: o técnico já possui reserva no período." if conflicts.empty?

      details = conflicts.map { |allocation| describe(allocation) }.uniq
      "Conflito de agenda: #{details.join("; ")}."
    end

    def describe(allocation)
      name = allocation.membership.user.name
      local = ->(time) { I18n.l(time.in_time_zone, format: :short) }
      what = allocation.kind == "absence" ? "ausência (#{allocation.reason})" : "visita da #{allocation.visit.work_order.number}"
      "#{name} tem #{what} de #{local.call(allocation.starts_at)} a #{local.call(allocation.ends_at)}"
    end
  end
end

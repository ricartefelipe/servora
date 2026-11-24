# frozen_string_literal: true

module Portal
  # Upcoming visits to the customer's locations.
  class VisitsController < BaseController
    def index
      @visits = Visit.joins(:work_order).merge(customer_scope(WorkOrder)).where(status: %w[scheduled in_progress])
        .where(scheduled_end: Time.current..).includes(work_order: :service_location).order(:scheduled_start).limit(50)
    end
  end
end

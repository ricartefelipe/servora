# frozen_string_literal: true

module Portal
  # Upcoming visits to the customer's locations.
  class VisitsController < BaseController
    def index
      @visits = Visit.joins(:work_order).merge(customer_scope(WorkOrder)).merge(Visit.where(status: Visits::IN_FIELD).or(Visit.where(
        status: "scheduled", scheduled_end: Time.current..
      ))).includes(work_order: :service_location).order(:scheduled_start).limit(50)
    end
  end
end

# frozen_string_literal: true

module Preventive
  # Daily generation of preventive occurrences. Each plan runs in its own
  # tenant transaction: a failing plan does not block the others, and the job
  # can run again at any time without duplicating occurrences.
  class GenerateDueJob < ApplicationJob
    queue_as :default

    def perform(today = nil)
      date = today ? Date.iso8601(today) : nil
      Servora::ActiveOrganizations.each_id do |organization_id|
        plan_ids(organization_id).each { |plan_id| generate(organization_id, plan_id, date) }
      end
    end

    private

    def plan_ids(organization_id)
      Servora::Tenancy.with_organization(organization_id) { MaintenancePlan.active.order(:id).pluck(:id) }
    end

    def generate(organization_id, plan_id, date)
      Servora::Tenancy.with_organization(organization_id) do
        plan = MaintenancePlan.find(plan_id)
        Preventive::GenerateOccurrences.new(plan:, today: date || Time.zone.today).call
      end
    rescue Servora::RuleViolation, ActiveRecord::RecordInvalid => e
      Rails.logger.warn(Servora::StructuredLog.line(event: "preventive.generation_failed", plan_id:, error_class: e.class.name,
        message: e.message))
    end
  end
end

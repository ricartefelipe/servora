# frozen_string_literal: true

module Sla
  # Replaces the SLA policies and the weekly business hours in one transaction.
  # Clocks already running keep the targets they started with.
  class Configure
    def initialize(organization:, form:, actor:)
      @organization = organization
      @form = form
      @actor = actor
    end

    def call
      policies = @form.policy_rows
      hours = @form.hour_rows
      ActiveRecord::Base.transaction(requires_new: true) do
        replace_policies(policies)
        replace_hours(hours)
        AuditEvent.record!(action: "sla.configured", organization: @organization, auditable: @organization,
          changes: { policies: policies.size, intervals: hours.size })
      end
    end

    private

    def replace_policies(rows)
      SlaPolicy.where.not(priority: rows.pluck(:priority)).delete_all
      rows.each do |row|
        policy = SlaPolicy.find_or_initialize_by(priority: row[:priority])
        policy.update!(row.except(:priority).merge(organization_id: @organization.id))
      end
    end

    def replace_hours(rows)
      BusinessHour.delete_all
      rows.each do |weekday, start_minute, end_minute|
        BusinessHour.create!(organization_id: @organization.id, weekday:, start_minute:, end_minute:)
      end
      overlapping = rows.group_by(&:first).any? { |_, list| list.sort.each_cons(2).any? { |a, b| b[1] < a[2] } }
      raise Servora::RuleViolation, "Os intervalos de um mesmo dia não podem se sobrepor." if overlapping
    end
  end
end

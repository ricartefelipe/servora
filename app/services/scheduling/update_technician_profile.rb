# frozen_string_literal: true

module Scheduling
  # Replaces a technician's skills and weekly working hours.
  class UpdateTechnicianProfile
    class InvalidSchedule < Servora::RuleViolation; end

    def initialize(membership:, skill_ids:, schedules:, new_skill: nil)
      @membership = membership
      @skill_ids = Array(skill_ids).compact_blank
      # Form fields arrive as an index-keyed hash ({"0" => {...}}) or an array.
      @schedules = schedules.respond_to?(:values) ? schedules.values : Array(schedules)
      @new_skill = new_skill.to_s.squish.presence
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        replace_skills
        replace_schedules
        AuditEvent.record!(action: "technician.profile_updated", auditable: @membership,
          changes: { skills: @membership.skills.reload.map(&:name), shifts: @membership.work_schedules.reload.map(&:label) })
      end
      @membership
    end

    private

    def replace_skills
      ids = @skill_ids
      ids += [Skill.find_or_create_by!(organization_id: @membership.organization_id, name: @new_skill).id] if @new_skill
      @membership.membership_skills.where.not(skill_id: ids).delete_all
      (ids - @membership.membership_skills.pluck(:skill_id)).uniq.each do |skill_id|
        MembershipSkill.create!(organization_id: @membership.organization_id, membership: @membership, skill_id:)
      end
    end

    def replace_schedules
      WorkSchedule.where(membership_id: @membership.id).delete_all
      @schedules.each do |row|
        next if row[:start].blank? || row[:end].blank?

        WorkSchedule.create!(organization_id: @membership.organization_id, membership: @membership,
          weekday: Integer(row[:weekday]), start_minute: minutes(row[:start]), end_minute: minutes(row[:end]))
      end
    end

    def minutes(text)
      hours, mins = text.to_s.split(":").map { |part| Integer(part, 10) }
      (hours * 60) + mins.to_i
    rescue ArgumentError, TypeError
      raise InvalidSchedule, "Horário inválido: #{text}"
    end
  end
end

# frozen_string_literal: true

module Preventive
  # Generates the occurrences of a plan whose window has opened, each with its
  # work order. Safe to run any number of times and concurrently:
  #
  # * the plan row lock serializes generators; last_sequence is re-read after
  #   locking;
  # * (plan, sequence) is unique in the database, so a duplicate can never be
  #   stored even if the lock were bypassed;
  # * a scheduler that was down catches up in order, at most MAX_PER_RUN per
  #   run, without skipping or repeating sequences.
  #
  # Calendar plans follow Preventive::Schedule; "after completion" plans only
  # generate the next occurrence once the previous work order is finished,
  # dated one period after the actual completion.
  class GenerateOccurrences
    MAX_PER_RUN = 12

    def initialize(plan:, today: Time.zone.today)
      @plan = plan
      @today = today
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        @plan.lock!
        contract = Contract.find(@plan.contract_id)
        next [] unless @plan.active? && contract.active?

        pending(contract).map { |sequence, due_on| generate(contract, sequence, due_on) }
      end
    end

    private

    def pending(contract)
      candidates = @plan.after_completion? ? next_after_completion : calendar_pending(contract)
      candidates.select { |_, due_on| contract.in_force_on?(due_on) }
    end

    def calendar_pending(contract)
      @plan.schedule.pending(last_sequence: @plan.last_sequence, today: @today, lead_days: @plan.lead_days,
        limit: MAX_PER_RUN, until_date: contract.ends_on)
    end

    def next_after_completion
      return first_occurrence if @plan.last_sequence.zero?

      finished_at = previous_finished_at
      return [] unless finished_at

      due_on = @plan.frequency.advance(finished_at.to_date, 1)
      due_on - @plan.lead_days <= @today ? [[@plan.next_sequence, due_on]] : []
    end

    def first_occurrence
      @plan.schedule.pending(last_sequence: 0, today: @today, lead_days: @plan.lead_days, limit: 1)
    end

    # Completion (or cancellation) instant of the previous occurrence's work
    # order; nil while it is still open.
    def previous_finished_at
      previous = WorkOrder.joins(:maintenance_occurrence)
        .find_by(maintenance_occurrences: { maintenance_plan_id: @plan.id, sequence: @plan.last_sequence })
      return nil unless previous&.finished?

      previous.completed_at || previous.canceled_at
    end

    def generate(contract, sequence, due_on)
      work_order = WorkOrders::Create.new(
        organization: contract.organization, actor: @plan.created_by,
        attributes: work_order_attributes(contract, sequence, due_on), equipment_ids: @plan.plan_equipment.map(&:equipment_id)
      ).call
      occurrence = MaintenanceOccurrence.create!(organization_id: @plan.organization_id, maintenance_plan: @plan, sequence:,
        due_on:, work_order:, generated_at: Time.current)
      @plan.update!(last_sequence: sequence)
      occurrence
    end

    def work_order_attributes(contract, sequence, due_on)
      {
        title: "#{@plan.title} — preventiva nº #{sequence}".truncate(160), origin: "preventive", priority: @plan.priority,
        customer_id: @plan.customer_id, service_location_id: @plan.service_location_id, service_type_id: @plan.service_type_id,
        contract_id: contract.id,
        problem_description: [@plan.instructions.presence, scheduled_note(sequence, due_on)].compact.join("\n\n")
      }
    end

    def scheduled_note(sequence, due_on)
      "Manutenção preventiva programada para #{I18n.l(due_on)} (plano #{@plan.title}, ocorrência #{sequence})."
    end
  end
end

# frozen_string_literal: true

module Seeds
  module DemoActivity
    module HistoryPlan
      # The hand-written part of the story (EVENTS) seen by the routine plan
      # (see HistoryPlan): its orders are reserved first in RoutineBook, so
      # the routine work follows the same rules around them, and its visits
      # take the technicians' time.
      module WrittenWork
        private

        # The rules start from the hand-written orders of the story.
        def routine_book
          customers = routine_customers.to_h { |data| [data[:document], [data[:kind], data[:equipment].size]] }
          RoutineBook.new(customers).tap do |book|
            written_orders.each { |job, date| book.record(job, date) }
          end
        end

        # [job, request date] of the orders written by hand (EVENTS).
        def written_orders
          events = self.class::EVENTS
          quotes = events.filter_map { |_, _, action, params| [params[:key], params[:customer]] if action == :quote }.to_h
          plans = events.filter_map { |_, _, action, params| [params[:key], params] if action == :contract }.to_h
          events.filter_map do |day, _, action, params|
            job = written_job(action, params, quotes, plans)
            job && [job, written_date(day)]
          end
        end

        def written_job(action, params, quotes, plans)
          case action
          when :open_order then written_order(params)
          when :portal_request
            { kind: :corrective, customer: customer_of(params[:contact]), equipment: [params[:equipment]].compact }
          when :convert_quote then { kind: :written, customer: quotes.fetch(params[:quote]), equipment: [] }
          when :generate
            plan = plans.fetch(params[:plan])
            { kind: :preventive, customer: plan[:customer], equipment: plan[:plan][:equipment] }
          end
        end

        # An order titled as a visit without a unit (RoutineCatalog::MISC) is
        # that visit: the routine history does not repeat it for the customer.
        def written_order(params)
          misc = RoutineCatalog::MISC.find { |template| template[:title] == params[:title] }
          return { kind: :misc, template: misc[:key], customer: params[:customer], equipment: [] } if misc

          kind = { self.class::CORRECTIVE => :corrective, self.class::PREVENTIVE => :preventive }[params[:service_type]]
          { kind: kind || :written, customer: params[:customer], equipment: params[:equipment] || [] }
        end

        def written_date(day)
          return (@risk_instant || instant(:today, "08:00")).in_time_zone(zone).to_date if day == :at_risk

          calendar_day(day)
        end

        def customer_of(email)
          routine_customers.find { |data| data[:contacts].any? { |contact| contact[1] == email } }.fetch(:document)
        end

        # Hand-written visits of `technician` on `date`: [[from, to + travel], ...].
        def busy_minutes(date, technician)
          @busy_minutes ||= written_visits.group_by(&:first).transform_values { |visits| visits.map(&:last).sort }
          @busy_minutes.fetch([date, technician], [])
        end

        # [[date, technician], [from, to + travel]] of the visits scheduled by
        # EVENTS for the days of the history.
        def written_visits
          self.class::EVENTS.flat_map do |_, _, action, params|
            next [] unless action == :schedule && params[:on].is_a?(Integer) && params[:on].negative?

            slot = [minutes(params[:from]), minutes(params[:to]) + HistoryPlan::TRAVEL]
            params[:technicians].map { |technician| [[calendar_day(params[:on]), technician], slot] }
          end
        end
      end
    end
  end
end

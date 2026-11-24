# frozen_string_literal: true

module Contracts
  # Whether a work order is covered by its contract: contract in force on the
  # request date, service type covered (no list means every service) and the
  # monthly visit limit not exceeded by earlier work orders of that month.
  class Coverage
    Result = Data.define(:covered, :reason, :used, :limit)

    def self.resolve(customer_id:, service_type_id:, on:)
      candidates = Contract.in_force_on(on).where(customer_id:).order(:number).includes(:contract_service_types).to_a
      candidates.find { |contract| covers_service?(contract, service_type_id) } || candidates.first
    end

    def self.covers_service?(contract, service_type_id)
      ids = contract.contract_service_types.map(&:service_type_id)
      ids.empty? || ids.include?(service_type_id)
    end

    def initialize(work_order)
      @work_order = work_order
      @contract = work_order.contract
    end

    def call
      date = @work_order.requested_at.to_date
      return Result.new(false, "Contrato fora de vigência na data da solicitação.", nil, nil) unless in_force?(date)
      unless self.class.covers_service?(@contract, @work_order.service_type_id)
        return Result.new(false, "Tipo de serviço não coberto pelo contrato.", nil, nil)
      end

      used = usage_before(date)
      limit = @contract.monthly_visit_limit
      return Result.new(false, "Limite mensal de atendimentos atingido.", used, limit) if limit && used >= limit

      Result.new(true, nil, used, limit)
    end

    private

    def in_force?(date)
      @contract.starts_on <= date && (@contract.ends_on.nil? || @contract.ends_on >= date) && @contract.status != "draft"
    end

    # Earlier work orders of the same month; (requested_at, id) is a total
    # order (UUIDv7 ids follow creation), so simultaneous requests still count.
    def usage_before(date)
      WorkOrder.where(contract_id: @contract.id).where.not(status: "canceled")
        .where(requested_at: date.beginning_of_month.in_time_zone..)
        .where("(work_orders.requested_at, work_orders.id) < (?, ?)", @work_order.requested_at, @work_order.id).count
    end
  end
end

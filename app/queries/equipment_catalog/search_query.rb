# frozen_string_literal: true

module EquipmentCatalog
  class SearchQuery
    def initialize(scope, term: nil, status: nil, customer_id: nil, include_archived: false)
      @scope = scope
      @term = term.to_s.strip.first(80)
      @status = status.presence_in(Equipment::STATUSES.keys)
      @customer_id = customer_id.presence
      @include_archived = include_archived
    end

    def call
      relation = @include_archived ? @scope : @scope.active
      relation = relation.where(operational_status: @status) if @status
      relation = relation.where(customer_id: @customer_id) if @customer_id
      relation = filter_term(relation) if @term.present?
      relation.order(:equipment_type, :manufacturer, :model)
    end

    private

    def filter_term(relation)
      like = "%#{ActiveRecord::Base.sanitize_sql_like(@term)}%"
      relation.left_joins(:customer).where(
        "equipment.serial_number ILIKE :like OR equipment.asset_tag ILIKE :like OR equipment.model ILIKE :like " \
        "OR equipment.manufacturer ILIKE :like OR equipment.equipment_type ILIKE :like OR customers.name ILIKE :like",
        like:
      )
    end
  end
end

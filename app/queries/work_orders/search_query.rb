# frozen_string_literal: true

module WorkOrders
  # Work order list: open work by default, urgent first, then oldest request.
  class SearchQuery
    PRIORITY_ORDER = Arel.sql(
      "CASE work_orders.priority WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 WHEN 'normal' THEN 2 ELSE 3 END"
    )

    def initialize(scope, status: nil, term: nil)
      @scope = scope
      @status = status
      @term = term.to_s.strip.first(80)
    end

    def call
      relation = @status ? @scope.where(status: @status) : @scope.open_work
      relation = filter_term(relation) if @term.present?
      relation.order(PRIORITY_ORDER, requested_at: :asc)
    end

    private

    def filter_term(relation)
      like = "%#{ActiveRecord::Base.sanitize_sql_like(@term)}%"
      relation.left_joins(:customer)
        .where("work_orders.number ILIKE :like OR work_orders.title ILIKE :like OR customers.name ILIKE :like", like:)
    end
  end
end

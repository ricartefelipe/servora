# frozen_string_literal: true

module WorkOrders
  # Work order list: open work by default, urgent first, then oldest request.
  # Narrows the scope it is given (already restricted by the policy) by state,
  # running deadline (prazo) and term.
  class SearchQuery
    PRIORITY_ORDER = Arel.sql(
      "CASE work_orders.priority WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 WHEN 'normal' THEN 2 ELSE 3 END"
    )

    # Deadline filter values in the URL (?prazo=), the WorkOrder scope each one
    # applies and their labels.
    DEADLINES = { "estourado" => :deadline_overdue, "em_risco" => :deadline_at_risk }.freeze
    DEADLINE_LABELS = { "estourado" => "Prazo estourado", "em_risco" => "Prazo em risco" }.freeze
    # Options of the list's select, which already sits under a "Prazo" label.
    DEADLINE_OPTIONS = { "estourado" => "Estourado", "em_risco" => "Em risco" }.freeze

    TERM_MAX_LENGTH = 80

    # The term as searched: blanks collapsed, at most TERM_MAX_LENGTH characters.
    # The list's filter summary shows this same value.
    def self.normalize_term(term) = term.to_s.squish.first(TERM_MAX_LENGTH).rstrip

    def initialize(scope, status: nil, term: nil, deadline: nil, now: Time.current)
      @scope = scope
      @status = status
      @term = self.class.normalize_term(term)
      @deadline = DEADLINES[deadline]
      @now = now
    end

    def call
      relation = @status ? @scope.where(status: @status) : @scope.open_work
      relation = relation.public_send(@deadline, @now) if @deadline
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

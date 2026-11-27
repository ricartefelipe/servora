# frozen_string_literal: true

# Presentation of work order states, shared by the office, field and portal
# views and the dashboard chart. Badges come from UiHelper#badge.
module WorkOrderStatusHelper
  # Neighbouring states never share a hue: approved (sky) before scheduled
  # (indigo), in progress (ember) apart from the waiting states (amber, marked
  # with a pause glyph because they pause the work and its resolution clock).
  TONES = {
    "open" => :neutral, "awaiting_approval" => :warning, "approved" => :info, "scheduled" => :indigo,
    "in_progress" => :ember, "waiting_parts" => :warning, "waiting_customer" => :warning, "completed" => :success,
    "reopened" => :warning, "canceled" => :neutral
  }.freeze

  MARKERS = { "waiting_parts" => :pause, "waiting_customer" => :pause }.freeze

  def work_order_status_tone(status) = TONES.fetch(status, :neutral)

  # Glyph shown instead of the dot for a state (nil keeps the dot).
  def work_order_status_marker(status) = MARKERS[status]

  # Running deadline marker of a list row (SlaClock.attention_by_work_order):
  # danger with the alert icon when past, warning with a clock when at risk.
  def work_order_deadline_badge(state)
    case state
    when :overdue then badge("Prazo estourado", tone: :danger)
    when :at_risk then badge("Prazo em risco", tone: :warning, marker: :clock)
    end
  end

  # Filters applied to the work order list, in reading order, for the empty
  # state and the table caption (status, deadline and search term).
  def work_order_filter_summary(filters)
    term = WorkOrders::SearchQuery.normalize_term(filters[:term])
    [("Situação: #{WorkOrders::LABELS[filters[:status]]}" if filters[:status]),
     WorkOrders::SearchQuery::DEADLINE_LABELS[filters[:deadline]],
     ("Busca: “#{term}”" if term.present?)].compact
  end

  # State badge: always the label, in the state hue and marker.
  def work_order_status_badge(status, label = WorkOrders::LABELS.fetch(status))
    badge(label, tone: work_order_status_tone(status), marker: work_order_status_marker(status))
  end
end

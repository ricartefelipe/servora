# frozen_string_literal: true

# Deadline tracking of one metric of a work order. Changed only by Sla::Track
# and Sla::Scan.
class SlaClock < TenantRecord
  METRICS = { "first_response" => "Primeira resposta", "resolution" => "Resolução" }.freeze
  STATUSES = { "running" => "Em andamento", "paused" => "Pausado", "met" => "Cumprido", "breached" => "Estourado",
               "canceled" => "Cancelado" }.freeze

  belongs_to :work_order
  has_many :events, -> { order(:occurred_at, :id) }, class_name: "SlaClockEvent", dependent: nil, inverse_of: :sla_clock

  scope :running, -> { where(status: "running") }
  # Running deadlines already past (estourados) and those inside the warning
  # window but not yet past (em risco). A work order may have one of each.
  scope :overdue, ->(now = Time.current) { running.where(due_at: ..now) }
  scope :at_risk, ->(now = Time.current) { running.where.not(due_at: ..now).where(warn_at: ..now) }

  # Most severe running deadline state of each given work order that has one:
  # { work_order_id => :overdue | :at_risk }.
  def self.attention_by_work_order(work_order_ids, now: Time.current)
    overdue(now).or(at_risk(now)).where(work_order_id: work_order_ids).pluck(:work_order_id, :due_at)
      .group_by(&:first).transform_values { |rows| rows.any? { |_id, due_at| due_at <= now } ? :overdue : :at_risk }
  end

  def metric_label = METRICS.fetch(metric)
  def status_label = STATUSES.fetch(status)
  def running? = status == "running"
  def paused? = status == "paused"
  def stopped? = %w[met breached canceled].include?(status)
  def overdue?(now = Time.current) = running? && due_at <= now
  def at_risk?(now = Time.current) = running? && !overdue?(now) && warn_at && warn_at <= now
  def remaining_seconds = [target_seconds - consumed_seconds, 0].max
end

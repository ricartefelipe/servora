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

  def metric_label = METRICS.fetch(metric)
  def status_label = STATUSES.fetch(status)
  def running? = status == "running"
  def paused? = status == "paused"
  def stopped? = %w[met breached canceled].include?(status)
  def overdue?(now = Time.current) = running? && due_at <= now
  def at_risk?(now = Time.current) = running? && !overdue?(now) && warn_at && warn_at <= now
  def remaining_seconds = [target_seconds - consumed_seconds, 0].max
end

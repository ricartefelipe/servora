# frozen_string_literal: true

# The story definitions (no seed runs when they are loaded), so specs can
# stub their constants before loading the seeds.
require Rails.root.join("db/seeds/support/demo_activity").to_s

# Shared by the specs that load db/seeds.rb with the demonstration activity
# (spec/database/demo_activity_*_spec.rb).
module DemoStoryHelpers
  ZONE = "America/Sao_Paulo"

  # Columns that record something that already happened (never after the run).
  PAST_COLUMNS = {
    "WorkOrder" => %i[created_at requested_at started_at completed_at], "WorkOrderTransition" => %i[created_at],
    "Visit" => %i[created_at travel_started_at started_at finished_at], "VisitTransition" => %i[created_at],
    "TimeEntry" => %i[started_at ended_at], "StockMovement" => %i[occurred_at created_at],
    "MaterialConsumption" => %i[created_at], "Receivable" => %i[created_at], "Payment" => %i[paid_at created_at],
    "Quote" => %i[created_at], "QuoteVersion" => %i[sent_at decided_at], "QuoteEvent" => %i[created_at],
    "AuditEvent" => %i[created_at], "Notification" => %i[created_at read_at], "OutboxEvent" => %i[created_at processed_at],
    "SlaClock" => %i[started_at stopped_at warned_at breach_notified_at], "SlaClockEvent" => %i[occurred_at],
    "EquipmentEvent" => %i[occurred_at], "WorkOrderReport" => %i[created_at], "PortalAccessGrant" => %i[created_at]
  }.freeze

  # Effect of each movement kind on the on-hand and reserved quantities.
  ON_HAND = { "entry" => 1, "return" => 1, "transfer_in" => 1, "adjustment_in" => 1, "consumption" => -1,
              "transfer_out" => -1, "adjustment_out" => -1 }.freeze
  RESERVED = { "reservation" => 1, "reservation_release" => -1 }.freeze

  def local(*) = Time.find_zone!(ZONE).local(*)
  def in_zone(time) = time.in_time_zone(ZONE)
  def whole_day(date) = date.in_time_zone(ZONE).all_day

  def enable_demo_activity
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("SEED_DEMO_ACTIVITY", anything).and_return("1")
  end

  def load_seeds = silence_warnings { load Rails.root.join("db/seeds.rb").to_s }
  def organization_id(key) = Seeds::ORGANIZATIONS.fetch(key)[:id]
  def member(email) = Membership.joins(:user).includes(:user).find_by!(users: { email: })

  # { "Diego" => ["completed", "in_progress"], ... }: visits of each technician on `date`, by start time.
  def agenda(date)
    Visit.where(scheduled_start: date.in_time_zone(ZONE).all_day).includes(allocations: { membership: :user })
      .order(:scheduled_start).each_with_object(Hash.new { |hash, name| hash[name] = [] }) do |visit, agenda|
        visit.allocations.map { |allocation| allocation.membership.user.name.split.first }.uniq
          .each { |name| agenda[name] << visit.status }
      end
  end

  # "Model.column" => count of rows dated after `now` (expected: none).
  def recorded_after(now)
    counts = PAST_COLUMNS.flat_map do |model, columns|
      columns.map { |column| ["#{model}.#{column}", model.constantize.where(column => (now + 1)..).count] }
    end
    counts.to_h.select { |_, count| count.positive? }
  end

  # Ledgers ([warehouse id, item id]) that do not add up when read by
  # occurred_at, or whose reading order differs from the recording order.
  def inconsistent_ledgers
    StockMovement.order(:occurred_at, :id).group_by { |movement| [movement.warehouse_id, movement.catalog_item_id] }
      .reject { |key, movements| ledger_consistent?(key, movements) }.keys
  end

  def ledger_consistent?((warehouse_id, item_id), movements)
    return false unless movements.map(&:id) == movements.map(&:id).sort

    position = movements.inject([BigDecimal("0"), BigDecimal("0")]) do |(on_hand, reserved), movement|
      after = apply_movement(on_hand, reserved, movement)
      return false unless after == [movement.on_hand_after, movement.reserved_after]

      after
    end
    position == StockBalance.where(warehouse_id:, catalog_item_id: item_id).pick(:on_hand, :reserved)
  end

  def apply_movement(on_hand, reserved, movement)
    released = movement.kind == "consumption" && movement.reservation_id ? movement.quantity : 0
    [on_hand + (ON_HAND.fetch(movement.kind, 0) * movement.quantity),
     reserved + (RESERVED.fetch(movement.kind, 0) * movement.quantity) - released]
  end

  # SLA clocks whose breach was notified without a warning before it.
  def sla_notices_out_of_order
    notices = SlaClockEvent.where(kind: %w[warned breached]).group_by(&:sla_clock_id)
      .transform_values { |events| events.to_h { |event| [event.kind, event.occurred_at] } }
    notices.select { |_, at| at["breached"] && (at["warned"].nil? || at["warned"] >= at["breached"]) }.keys
  end

  # Portal links recorded at another instant than a sending of their quote.
  def portal_links_after_sending
    sent = QuoteEvent.where(kind: "sent").group_by(&:quote_id).transform_values { |events| events.map(&:created_at) }
    QuoteEvent.where(kind: "portal_link_sent").reject { |event| sent.fetch(event.quote_id, []).include?(event.created_at) }
      .map(&:quote_id)
  end

  # Runs the block with the seeds' progress messages silenced.
  def quietly
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end
end

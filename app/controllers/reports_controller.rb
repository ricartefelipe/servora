# frozen_string_literal: true

# Management reports for a period, with CSV export (audited).
class ReportsController < TenantController
  include FileDelivery

  before_action :prepare

  # Reports are tenant-wide aggregates: access is decided by ReportPolicy and
  # the rows are restricted by Row-Level Security (no record-level scope).
  def index
    skip_policy_scope
    @selected = params[:relatorio].presence_in(@available) || @available.first # rubocop:disable Rails/StrongParametersExpect -- optional selection
    @report = build(@selected)
    @rows = @report.rows(limit: Reports::Base::SCREEN_ROWS)
  end

  def export
    key = params.expect(:relatorio)
    raise ActiveRecord::RecordNotFound unless @available.include?(key)

    report = build(key)
    AuditEvent.record!(action: "report.exported", auditable: current_organization,
      changes: { report: key, from: @period.from, to: @period.to })
    deliver_file(Reports::CsvExport.generate(report), type: "text/csv; charset=utf-8",
      filename: "servora-#{key}-#{@period.from.iso8601}-#{@period.to.iso8601}.csv")
  end

  private

  def prepare
    authorize :report, :show?
    @period = Reports::Period.parse(from: params[:de], to: params[:ate],
      today: Time.current.in_time_zone(current_organization.zone).to_date)
    report_policy = policy(:report)
    @available = Reports::Catalog.available(policy: report_policy, module_enabled: ->(code) { module_enabled?(code) })
    @show_costs = report_policy.costs?
  end

  def build(key) = Reports::Catalog.build(key, period: @period, zone: current_organization.zone, show_costs: @show_costs)
end

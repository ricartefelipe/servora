# frozen_string_literal: true

class SlaSettingsController < TenantController
  POLICY_FIELDS = %i[enabled first_response resolution business_hours_only warning_percent].freeze
  HOUR_FIELDS = %i[start1 end1 start2 end2].freeze
  PERMITTED = [{
    policies: WorkOrder::PRIORITIES.keys.to_h { |priority| [priority.to_sym, POLICY_FIELDS] },
    hours: (0..6).to_h { |weekday| [weekday.to_s.to_sym, HOUR_FIELDS] }
  }].freeze

  before_action :authorize_settings

  def show
    @form = SlaSettingsForm.load
    load_holidays
  end

  def update
    attributes = params.expect(sla: PERMITTED)
    @form = SlaSettingsForm.new(policies: attributes[:policies].to_h, hours: attributes[:hours].to_h)
    Sla::Configure.new(organization: current_organization, form: @form, actor: current_membership).call
    redirect_to sla_settings_path, notice: "Prazos e expediente salvos. Prazos já em contagem não mudam.", status: :see_other
  rescue Servora::RuleViolation, ActiveRecord::RecordInvalid => e
    flash.now[:alert] = e.is_a?(ActiveRecord::RecordInvalid) ? e.record.errors.full_messages.to_sentence : e.message
    load_holidays
    render :show, status: :unprocessable_content
  end

  private

  def authorize_settings = authorize(current_organization, :update?)

  def load_holidays
    @holidays = tenant_relation(Holiday).where(date: Time.zone.today.beginning_of_year..).upcoming_first
    @holiday = Holiday.new
  end
end

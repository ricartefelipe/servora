# frozen_string_literal: true

class HolidaysController < TenantController
  def create
    authorize current_organization, :update?
    holiday = Holiday.new(params.expect(holiday: %i[date name]).merge(organization_id: current_organization.id))
    if holiday.save
      AuditEvent.record!(action: "holiday.created", auditable: holiday, changes: { date: holiday.date, name: holiday.name })
      redirect_to sla_settings_path(anchor: "feriados"), notice: "Feriado cadastrado.", status: :see_other
    else
      redirect_to sla_settings_path(anchor: "feriados"), alert: holiday.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    authorize current_organization, :update?
    holiday = tenant_relation(Holiday).find(params.expect(:id))
    holiday.destroy!
    AuditEvent.record!(action: "holiday.removed", auditable: holiday, changes: { date: holiday.date })
    redirect_to sla_settings_path(anchor: "feriados"), notice: "Feriado removido.", status: :see_other
  end
end

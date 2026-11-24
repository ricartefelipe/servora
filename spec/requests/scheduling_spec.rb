# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Scheduling" do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:work_order) { open_work_order(scenario) }
  let!(:diego) { create_technician(organization, name: "Diego Alves") }

  def schedule_params(start_time:, technicians: [diego])
    { visit: { date: "2026-12-01", start_time:, duration_minutes: "60", travel_minutes: "30",
               technician_ids: technicians.map(&:id) } }
  end

  it "schedules a visit and shows it on the day agenda" do
    sign_in_as(scenario[:coordinator])

    post work_order_visits_path(work_order), params: schedule_params(start_time: "09:00")
    get agenda_index_path(data: "2026-12-01")

    expect(response.body).to include(work_order.number, "Diego Alves", "col-start-13 col-span-6")
  end

  it "shows the conflict and keeps the form when the technician is already booked" do
    sign_in_as(scenario[:coordinator])
    post work_order_visits_path(work_order), params: schedule_params(start_time: "09:00")
    other = open_work_order(scenario, title: "Outra")

    post work_order_visits_path(other), params: schedule_params(start_time: "09:45")

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Conflito de agenda", "Diego Alves tem visita da #{work_order.number}")
  end

  it "renders suggestions in a frame" do
    sign_in_as(scenario[:coordinator])

    get suggestions_work_order_visits_path(work_order, date: "2026-12-01", start_time: "09:00", duration_minutes: 60)

    expect(response.body).to include('id="visit-suggestions"', "Diego Alves")
  end

  it "limits technicians to their own agenda" do
    other_tech = create_technician(organization, name: "Eduarda Lima")
    schedule(scenario, work_order, [diego], from: tuesday_at(9), to: tuesday_at(10))
    schedule(scenario, open_work_order(scenario, title: "X"), [other_tech], from: tuesday_at(13), to: tuesday_at(14))
    sign_in_as(diego)

    get agenda_index_path(data: "2026-12-01", visao: "semana")

    expect(response.body).to include("Diego Alves")
    expect(response.body).not_to include("Eduarda Lima")
    post work_order_visits_path(work_order), params: schedule_params(start_time: "15:00")
    expect(response).to have_http_status(:forbidden)
  end

  it "registers absences that block the agenda" do
    sign_in_as(scenario[:coordinator])

    post absences_path, params: { absence: { membership_id: diego.id, starts_at: "2026-12-01T08:00", ends_at: "2026-12-01T18:00",
                                             reason: "Férias" } }
    post work_order_visits_path(work_order), params: schedule_params(start_time: "10:00")

    expect(response.body).to include("ausência (Férias)")
  end

  it "updates skills and working hours of a technician" do
    sign_in_as(scenario[:coordinator])

    patch technician_path(diego), params: { technician: { new_skill: "Elétrica predial",
                                                          schedules: { "2" => { weekday: "1", start: "07:00", end: "16:00" } } } }

    in_tenant(organization) do
      expect(diego.reload.skills.map(&:name)).to eq(["Elétrica predial"])
      expect(diego.work_schedules.map(&:label)).to eq(["Segunda 07:00–16:00"])
    end
  end

  it "starts and finishes a visit from the work order without completing it" do
    visit = schedule(scenario, work_order, [diego], from: tuesday_at(9), to: tuesday_at(10))
    sign_in_as(diego)

    patch start_work_order_visit_path(work_order, visit)
    patch finish_work_order_visit_path(work_order, visit),
      params: { finish: { outcome_note: "Aguardando peça", needs_return: "1" } }

    expect(in_tenant(organization) { [visit.reload.status, work_order.reload.status] }).to eq(%w[completed in_progress])
  end
end

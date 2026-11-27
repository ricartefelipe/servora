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

    # Diego works 08:00–18:00: the 09:00 visit (plus 30 minutes of travel) starts at the fifth 15-minute column.
    expect(response.body).to include(work_order.number, "Diego Alves", "col-start-5 col-span-6")
  end

  it "proposes the next business day at 09:00, after the weekend and the organization's holidays" do
    in_tenant(organization) { Holiday.create!(organization:, date: Date.new(2026, 11, 30), name: "Feriado municipal") }
    travel_to(tuesday_at(10) - 4.days) do # Friday
      sign_in_as(scenario[:coordinator])
      get new_work_order_visit_path(work_order)
    end

    form = response.parsed_body
    expect(form.at_css("input[name='visit[date]']")["value"]).to eq("2026-12-01")
    expect(form.at_css("input[name='visit[start_time]']")["value"]).to eq("09:00")
    expect(form.at_css("turbo-frame#visit-suggestions")["src"]).to include("date=2026-12-01", "start_time=09%3A00")
  end

  describe "hours of the day timeline" do
    def timeline_hours
      response.parsed_body.css("section[aria-label='Linha do tempo do dia'] div[aria-hidden=true] > div.grid > span")
        .map(&:text)
    end

    it "fits the working hours of the technicians shown" do
      sign_in_as(scenario[:coordinator])

      get agenda_index_path(data: "2026-12-01")

      expect(timeline_hours).to eq((8...18).map { |hour| format("%02d:00", hour) })
      lane = response.parsed_body.at_css("section[aria-label='Linha do tempo do dia'] ul[role=list] > li > div.grid")
      expect(lane["class"].split).to include("grid-cols-[repeat(40,minmax(0,1fr))]", "bg-[length:calc(100%/10)_100%]")
    end

    it "widens to the allocations outside them, never beyond 06:00–22:00" do
      as_member(scenario[:coordinator]) do
        Scheduling::ScheduleVisit.new(work_order: WorkOrder.includes(:organization).find(work_order.id),
          starts_at: tuesday_at(18, 30), ends_at: tuesday_at(20, 15), technicians: [diego], actor: scenario[:coordinator],
          travel_minutes: 0, enforce_working_hours: false).call
      end
      sign_in_as(scenario[:coordinator])

      get agenda_index_path(data: "2026-12-01")

      expect(timeline_hours.values_at(0, -1)).to eq(%w[08:00 20:00])
      expect(response.body).to include("col-start-43 col-span-7")
    end

    it "keeps the whole range when nobody has working hours that day" do
      sign_in_as(scenario[:coordinator])

      get agenda_index_path(data: "2026-12-06")

      expect(timeline_hours.values_at(0, -1)).to eq(%w[06:00 21:00])
    end
  end

  it "shows the whole period only on blocks of 2.5 hours or more, the start elsewhere, and never cuts the order number" do
    middle_order = open_work_order(scenario, title: "Média")
    long_order = open_work_order(scenario, title: "Longa")
    schedule(scenario, work_order, [diego], from: tuesday_at(8), to: tuesday_at(9))
    schedule(scenario, middle_order, [diego], from: tuesday_at(10), to: tuesday_at(12))
    schedule(scenario, long_order, [diego], from: tuesday_at(13), to: tuesday_at(15), travel: 30)
    sign_in_as(scenario[:coordinator])

    get agenda_index_path(data: "2026-12-01")

    timeline = response.parsed_body.at_css("section[aria-label='Linha do tempo do dia']")
    short_block, middle_block, long_block = [work_order, middle_order, long_order]
      .map { |order| timeline.at_css("a[href='#{work_order_path(order)}']") }
    expect(short_block.css("> span")[1].text.squish).to eq("#{work_order.number} · 08:00")
    expect(middle_block.css("> span")[1].text.squish).to eq("#{middle_order.number} · 10:00")
    expect(long_block.css("> span")[1].text.squish).to eq("#{long_order.number} · 13:00–15:00")
    number = short_block.at_css("span.font-mono")
    expect(number["class"].split).to include("whitespace-nowrap", "shrink-0")
    expect(number["class"].split).not_to include("truncate")
    expect([short_block["title"], middle_block["aria-label"]]).to match([include("08:00–09:00"), include("10:00 às 12:00")])
  end

  it "moves the time, whole, to its own line when the block is too narrow for number and time" do
    schedule(scenario, work_order, [diego], from: tuesday_at(8), to: tuesday_at(9))
    sign_in_as(scenario[:coordinator])

    get agenda_index_path(data: "2026-12-01")

    block = response.parsed_body.at_css("section[aria-label='Linha do tempo do dia'] a[href='#{work_order_path(work_order)}']")
    expect(block["class"].split).to include("@container")
    inline_time = block.css("> span")[1].css("> span")[1]
    expect(inline_time["class"].split).to include("hidden", "@min-[8.75rem]:inline", "whitespace-nowrap")
    expect(inline_time["class"].split).not_to include("truncate")
    own_line = block.css("> span")[2]
    expect(own_line.text).to eq("08:00")
    expect(own_line["class"].split).to include("@min-[8.75rem]:hidden", "whitespace-nowrap")
    customer = in_tenant(organization) { scenario[:customer].reload.display_name }
    expect(block.css(".truncate").map { |node| node.text.squish }).to eq([customer])
  end

  describe "on phones" do
    it "lists the day by technician, one card per visit, instead of the timeline" do
      other = create_technician(organization, name: "Eduarda Lima")
      schedule(scenario, work_order, [diego], from: tuesday_at(9), to: tuesday_at(10))
      sign_in_as(scenario[:coordinator])

      get agenda_index_path(data: "2026-12-01")

      page = response.parsed_body
      list = page.at_css("[role=region][aria-label='Agenda em lista']")
      expect(list["class"].split).to include("md:hidden")
      expect(page.at_css("section[aria-label='Linha do tempo do dia']")["class"].split).to include("max-md:hidden")
      day = list.at_css("section")
      expect(day.at_css("h2").text.squish).to eq("Terça-feira, 01/12")
      expect(day.css("h3").map { |heading| heading.text.squish }).to eq(["Diego Alves 1 visita"])
      expect(day.text).not_to include(other.user.name)
      card = day.at_css("a[href='#{work_order_path(work_order)}']")
      customer = in_tenant(organization) { scenario[:customer].reload.display_name }
      expect(card.text.squish).to eq("09:00 às 10:00 #{customer} #{work_order.number} Agendada")
    end

    it "lists the week by day, saying when a day has no visit" do
      schedule(scenario, work_order, [diego], from: tuesday_at(9), to: tuesday_at(10))
      sign_in_as(scenario[:coordinator])

      get agenda_index_path(data: "2026-12-01", visao: "semana")

      page = response.parsed_body
      days = page.css("[aria-label='Agenda em lista'] > section")
      expect(days.size).to eq(7)
      expect(days.map { |day| day.at_css("h2").text.squish.split(",").first })
        .to eq(%w[Segunda-feira Terça-feira Quarta-feira Quinta-feira Sexta-feira Sábado Domingo])
      expect(days[1].at_css("a[href='#{work_order_path(work_order)}']")).to be_present
      expect(days[0].text).to include("Nenhuma visita.")
      expect(page.at_css("section[aria-label='Agenda da semana']")["class"].split).to include("max-md:hidden")
    end
  end

  it "leads each day block with the customer, then the order number, with the whole visit in a tooltip" do
    sign_in_as(scenario[:coordinator])
    post work_order_visits_path(work_order), params: schedule_params(start_time: "09:00")

    get agenda_index_path(data: "2026-12-01")

    timeline = response.parsed_body.at_css("section[aria-label='Linha do tempo do dia']")
    block = timeline.at_css("a[href='#{work_order_path(work_order)}']")
    customer = in_tenant(organization) { scenario[:customer].reload.display_name }
    lines = block.css("> span").map { |line| line.text.squish }
    expect(lines.first).to eq(customer)
    expect(lines.second).to start_with(work_order.number)
    expect(block["title"]).to eq("#{customer} · #{work_order.number} · 09:00–10:00 · Agendada")
    expect(block["aria-label"]).to start_with("#{customer}, #{work_order.number}, 09:00 às 10:00")
  end

  it "lays the week out in equal fixed columns that scroll inside the card" do
    sign_in_as(scenario[:coordinator])
    post work_order_visits_path(work_order), params: schedule_params(start_time: "09:00")

    get agenda_index_path(data: "2026-12-01", visao: "semana")

    page = response.parsed_body
    table = page.at_css("section[aria-label='Agenda da semana'] > div.overflow-x-auto > table")
    expect(table["class"].split).to include("table-fixed", "w-full")
    expect(table.css("colgroup col").size).to eq(8)
    expect(table.css("thead th").map(&:text).last.squish).to start_with("dom")
    number = table.at_css("a[href='#{work_order_path(work_order)}'] span.whitespace-nowrap")
    expect(number.text).to eq(work_order.number)
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

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboards::Today do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:coordinator) { scenario[:coordinator] }
  let(:zone) { ActiveSupport::TimeZone[organization.time_zone] }
  let(:tuesday) { Date.new(2026, 12, 1) }

  def at(text) = zone.parse(text)

  # Builds the query the way the controller does (policy-scoped visits and
  # stock) and evaluates the block inside the member's tenant context and zone.
  def on_dashboard(membership, visits: nil, stock_balances: nil, today: tuesday, now: tuesday_at(10))
    as_member(membership) do
      Time.use_zone(zone) do
        context = PolicyContext.new(user: membership.user, membership:)
        visits ||= VisitPolicy::Scope.new(context, Visit.where(organization_id: organization.id)).resolve
        stock_balances ||= StockBalancePolicy::Scope.new(context, StockBalance.where(organization_id: organization.id)).resolve
        yield described_class.new(membership:, visits:, stock_balances:, today:, now:)
      end
    end
  end

  def subscribe(plan_code)
    in_tenant(organization) do
      plan = Plan.find_by!(code: plan_code)
      Subscription.create!(organization:, plan:, status: "active", technician_seats: plan.included_technicians,
        monthly_amount: plan.monthly_price, activated_at: Time.current)
    end
  end

  describe "visits" do
    let(:technician) { create_technician(organization, name: "Diego") }

    def visit_at(from, to, title: "Visita")
      schedule(scenario, open_work_order(scenario, title:), [technician], from:, to:, travel: 0)
    end

    def start(visit, at:)
      in_tenant(organization) { Visits::Start.new(visit: visit.reload, actor: technician, at:).call }
    end

    def finish(visit, at:)
      in_tenant(organization) { Visits::Finish.new(visit: visit.reload, actor: technician, at:).call }
    end

    def cancel(visit, no_show: false)
      in_tenant(organization) do
        Visits::Cancel.new(visit: visit.reload, actor: coordinator, reason: "Cliente pediu outra data", no_show:).call
      end
    end

    describe "#cover" do
      let!(:visits) do
        {
          done: visit_at(tuesday_at(8), tuesday_at(9)),
          running: visit_at(tuesday_at(9), tuesday_at(10)),
          scheduled: visit_at(tuesday_at(10), tuesday_at(11)),
          canceled: visit_at(tuesday_at(11), tuesday_at(12)),
          no_show: visit_at(tuesday_at(13), tuesday_at(14)),
          tomorrow: visit_at(tuesday_at(9) + 1.day, tuesday_at(10) + 1.day),
          left_running: visit_at(tuesday_at(9) - 1.day, tuesday_at(10) - 1.day)
        }.tap do |all|
          start(all[:done], at: tuesday_at(8, 5))
          finish(all[:done], at: tuesday_at(8, 50))
          start(all[:running], at: tuesday_at(9, 5))
          start(all[:left_running], at: tuesday_at(9, 5) - 1.day)
          cancel(all[:canceled])
          cancel(all[:no_show], no_show: true)
        end
      end

      it "counts today's visits (without canceled or no-show), the completed ones and who is in the field" do
        cover = on_dashboard(coordinator, &:cover)

        expect(cover).to have_attributes(visits_total: 3, visits_done: 1, in_field: 2, open_orders: visits.size)
        expect(cover.progress).to eq(33)
      end

      it "honours the visits scope handed in by the caller" do
        narrowed = Visit.where(id: [visits[:done].id, visits[:canceled].id, visits[:tomorrow].id])

        cover = on_dashboard(coordinator, visits: narrowed, &:cover)

        expect(cover).to have_attributes(visits_total: 1, visits_done: 1, in_field: 0)
        expect(cover.progress).to eq(100)
      end

      it "shows no visit figures to members outside the agenda and hides open orders without the permission" do
        finance = create(:membership, :finance, organization:)
        member_without_orders = create(:membership, :technician, organization:)

        expect(on_dashboard(finance, &:cover))
          .to have_attributes(visits_total: 0, visits_done: 0, in_field: 0, open_orders: visits.size)
        expect(on_dashboard(member_without_orders, &:cover).open_orders).to be_nil
      end

      it "measures the day from the date it is given" do
        cover = on_dashboard(coordinator, today: tuesday + 1, &:cover)

        expect(cover).to have_attributes(visits_total: 1, visits_done: 0)
        expect(cover.progress).to eq(0)
      end
    end

    describe "#upcoming_visits" do
      let(:now) { tuesday_at(9, 10) }

      # Created out of chronological order so that ordering cannot come from ids.
      let!(:visits) do
        slots = [[14, 0], [13, 30], [13, 0], [11, 30], [11, 0], [10, 30], [10, 0], [9, 30], [9, 0], [8, 30], [8, 0]]
        all = slots.to_h do |hour, minute|
          from = tuesday_at(hour, minute)
          [format("%<hour>02d:%<minute>02d", hour:, minute:), visit_at(from, from + 30.minutes, title: "Visita #{hour}h")]
        end
        start(all["08:30"], at: tuesday_at(8, 30))
        finish(all["08:30"], at: tuesday_at(8, 55))
        start(all["09:00"], at: tuesday_at(9))
        cancel(all["09:30"])
        all
      end

      it "lists the next six visits still ahead (scheduled or in progress) in start order" do
        upcoming = on_dashboard(coordinator, now:, &:upcoming_visits)

        expect(upcoming.map(&:id)).to eq(visits.values_at("09:00", "10:00", "10:30", "11:00", "11:30", "13:00").map(&:id))
        expect(upcoming.size).to eq(described_class::UPCOMING_LIMIT)
        expect(upcoming.first.status).to eq("in_progress")
      end

      it "preloads the work order, customer and service location shown in each row" do
        upcoming = on_dashboard(coordinator, now:, &:upcoming_visits)

        expect(upcoming).to all(satisfy { |visit| visit.association(:work_order).loaded? })
        expect(upcoming.map(&:work_order)).to all(satisfy do |order|
          order.association(:customer).loaded? && order.association(:service_location).loaded?
        end)
      end

      it "honours the visits scope handed in by the caller" do
        narrowed = Visit.where(id: visits.values_at("08:00", "08:30", "13:30").map(&:id))

        upcoming = on_dashboard(coordinator, visits: narrowed, now:, &:upcoming_visits)

        expect(upcoming.map(&:id)).to eq([visits["13:30"].id])
        expect(on_dashboard(create(:membership, :finance, organization:), now:, &:upcoming_visits)).to be_empty
      end
    end
  end

  describe "#attention" do
    let(:now) { at("2026-11-24 17:00") }
    let(:today) { Date.new(2026, 11, 24) }
    let(:owner) { create(:membership, :owner, organization:) }
    let(:warehouse) { create(:warehouse, organization:) }

    def attention(membership, **) = on_dashboard(membership, today:, now:, **, &:attention)
    def areas(membership) = on_dashboard(membership, today:, now:, &:areas_checked)
    def keys(membership) = attention(membership).map(&:key)

    def equipment_with(status, archived: false)
      equipment = create(:equipment, location: scenario[:location])
      in_tenant(organization) do
        equipment.update_columns(operational_status: status, archived_at: (Time.current if archived))
      end
      equipment
    end

    def below_minimum(quantity:, minimum:)
      item = stock_part(organization)
      receive_stock(warehouse, item, quantity, "10")
      in_tenant(organization) { Inventory::SetMinimum.new(warehouse:, item:, minimum:, actor: nil).call }
    end

    def overdue_receivable
      work_order = travel_to(at("2026-11-20 09:00")) { open_work_order(scenario, title: "Faturada", priority: "low") }
      add_authorized_item(scenario, work_order, unit_price: "500.00")
      travel_to(at("2026-11-20 10:00")) { issue_receivable(scenario, work_order, "500", due_on: Date.new(2026, 11, 21)) }
    end

    context "with something pending in every area" do
      before do
        configure_sla(organization)
        # First response due 11:00 (breached); resolution due 18:00, warning from 16:24 (at risk).
        travel_to(at("2026-11-24 09:00")) { open_work_order(scenario) }
        equipment_with("inoperative")
        equipment_with("inoperative", archived: true)
        equipment_with("attention")
        equipment_with("attention")
        below_minimum(quantity: "2", minimum: "5")
        below_minimum(quantity: "9", minimum: "5")
        overdue_receivable
      end

      it "lists every area for the owner, high severity before medium" do
        items = attention(owner)

        expect(items.map(&:key)).to eq(%i[sla_breached equipment_inoperative receivables_overdue
                                          sla_at_risk equipment_attention stock_below_minimum])
        expect(items.map(&:severity)).to eq(%i[high high high medium medium medium])
        expect(items.map(&:count)).to eq([1, 1, 1, 1, 2, 1])
      end

      it "links each item to the pre-filtered list where it is resolved" do
        items = attention(owner).index_by(&:key)

        expect(items[:receivables_overdue]).to have_attributes(label: "Contas vencidas", route: :receivables_path,
          params: { situacao: "overdue" })
        expect(items[:equipment_inoperative]).to have_attributes(route: :equipment_index_path, params: { estado: "inoperative" })
        expect(items[:stock_below_minimum]).to have_attributes(route: :stock_balances_path, params: { abaixo: "1" })
        expect(items[:sla_breached]).to have_attributes(label: "OS com prazo estourado", route: :work_orders_path)
      end

      it "follows the member's permissions" do
        expect(keys(coordinator)).to eq(%i[sla_breached equipment_inoperative sla_at_risk equipment_attention
                                           stock_below_minimum])
        expect(keys(create(:membership, :finance, organization:)))
          .to eq(%i[sla_breached receivables_overdue sla_at_risk stock_below_minimum])
        expect(keys(create(:membership, :attendant, organization:))).not_to include(:receivables_overdue)
      end

      it "counts stock only in the balances handed in by the caller" do
        technician = scenario[:technician]

        expect(keys(technician)).to eq(%i[equipment_inoperative equipment_attention])
        expect(attention(coordinator, stock_balances: StockBalance.none).map(&:key)).not_to include(:stock_below_minimum)
      end

      it "leaves out finance and inventory when the plan does not include them" do
        subscribe("essencial")

        expect(keys(owner)).to eq(%i[sla_breached equipment_inoperative sla_at_risk equipment_attention])
        expect(areas(owner)).to eq(4)
      end

      it "keeps inventory and drops finance on a plan with inventory only" do
        subscribe("profissional")

        expect(keys(owner)).to eq(%i[sla_breached equipment_inoperative sla_at_risk equipment_attention
                                     stock_below_minimum])
      end

      it "honours the dates it is given" do
        on_time = on_dashboard(owner, today: Date.new(2026, 11, 21), now: at("2026-11-24 09:30"), &:attention)

        expect(on_time.map(&:key)).to eq(%i[equipment_inoperative equipment_attention stock_below_minimum])
      end
    end

    it "omits areas with nothing pending while still counting them as checked" do
      expect(attention(coordinator)).to be_empty
      expect(attention(owner)).to be_empty
      expect([areas(coordinator), areas(owner)]).to eq([5, 6])
    end

    it "checks only the areas the member may see" do
      expect(areas(scenario[:technician])).to eq(3)
      expect(areas(create(:membership, :finance, organization:))).to eq(4)
      expect(areas(create(:membership, :auditor, organization:))).to eq(6)
    end
  end

  describe "#open_orders_by_status" do
    def order_in(status)
      order = open_work_order(scenario)
      finished = { "completed" => { completed_at: Time.current },
                   "canceled" => { canceled_at: Time.current, cancel_reason: "Cliente desistiu" } }
      in_tenant(organization) { order.update_columns(status:, **finished.fetch(status, {})) }
      order
    end

    before do
      %w[in_progress open scheduled open waiting_parts completed canceled].each { |status| order_in(status) }
    end

    it "counts the open work orders per status in lifecycle order, leaving out finished and empty statuses" do
      slices = on_dashboard(coordinator, &:open_orders_by_status)

      expect(slices.map { |slice| [slice.status, slice.label, slice.count] })
        .to eq([["open", "Aberta", 2], ["scheduled", "Agendada", 1], ["in_progress", "Em execução", 1],
                ["waiting_parts", "Aguardando peças", 1]])
      expect(slices.sum(&:count)).to eq(on_dashboard(coordinator, &:cover).open_orders)
    end

    it "is only available to members who see every work order" do
      expect(on_dashboard(create(:membership, :finance, organization:), &:open_orders_by_status).sum(&:count)).to eq(5)
      expect(on_dashboard(scenario[:technician], &:open_orders_by_status)).to be_nil
    end

    it "never counts another organization's work orders" do
      build_work_order_scenario.then { |other| open_work_order(other) }

      expect(on_dashboard(coordinator, &:open_orders_by_status).sum(&:count)).to eq(5)
    end
  end

  describe "#daily_receipts" do
    let(:finance) { create(:membership, :finance, organization:) }
    let(:receivable) do
      work_order = travel_to(at("2026-11-20 09:00")) { open_work_order(scenario, title: "Faturada") }
      add_authorized_item(scenario, work_order, unit_price: "5000.00")
      travel_to(at("2026-11-20 10:00")) { issue_receivable(scenario, work_order, "5000", due_on: Date.new(2026, 12, 20)) }
    end

    def paid(amount, at:, on: receivable)
      travel_to(tuesday_at(23, 50)) do
        in_tenant(organization) do
          Receivables::RegisterPayment.new(receivable: on.reload, amount:, payment_method: "pix", actor: nil, paid_at: at).call
        end
      end
    end

    def refund(payment, amount)
      in_tenant(organization) do
        Receivables::RefundPayment.new(payment: payment.reload, amount:, reason: "Cobrança em duplicidade", actor: nil).call
      end
    end

    def amounts(receipts) = receipts.to_h { |receipt| [receipt.date, receipt.amount] }

    it "returns the last seven days ending today, with empty days at zero" do
      receipts = on_dashboard(finance, &:daily_receipts)

      expect(receipts.map(&:date)).to eq((Date.new(2026, 11, 25)..tuesday).to_a)
      expect(receipts.map(&:amount)).to all(eq(0))
      expect(receipts.map(&:today)).to eq(([false] * 6) + [true])
    end

    it "adds up each day's payments, net of refunds" do
      paid("100.00", at: at("2026-11-27 09:00"))
      partially_refunded = paid("300.00", at: at("2026-11-27 15:00"))
      refund(partially_refunded, "120.00")
      refund(paid("50.00", at: at("2026-11-28 10:00")), "50.00")
      paid("75.50", at: tuesday_at(8))

      receipts = amounts(on_dashboard(finance, &:daily_receipts))

      expect(receipts[Date.new(2026, 11, 27)]).to eq(BigDecimal("280.00"))
      expect(receipts[Date.new(2026, 11, 28)]).to eq(0)
      expect(receipts[tuesday]).to eq(BigDecimal("75.50"))
      expect(receipts.values.sum).to eq(BigDecimal("355.50"))
    end

    it "places each payment on the organization's calendar day" do
      paid("10.00", at: at("2026-11-24 23:59"))
      paid("20.00", at: at("2026-11-25 00:00"))
      paid("30.00", at: at("2026-11-30 23:30")) # already Tuesday in UTC
      paid("40.00", at: at("2026-12-01 00:10"))

      receipts = amounts(on_dashboard(finance, &:daily_receipts))

      expect(receipts.values.sum).to eq(BigDecimal("90.00"))
      expect(receipts.values_at(Date.new(2026, 11, 25), Date.new(2026, 11, 30), tuesday))
        .to eq([20, 30, 40].map { BigDecimal(it) })
    end

    it "follows the organization's time zone even when the request runs in another one" do
      in_tenant(organization) { organization.update!(time_zone: "America/Rio_Branco") }
      rio_branco = ActiveSupport::TimeZone["America/Rio_Branco"]
      paid("30.00", at: rio_branco.parse("2026-11-30 22:30")) # 00:30 on Tuesday in Brasília

      receipts = as_member(finance) do
        Time.use_zone("America/Sao_Paulo") do
          described_class.new(membership: finance.reload, visits: Visit.none, stock_balances: StockBalance.none,
            today: tuesday).daily_receipts
        end
      end

      expect(amounts(receipts).values_at(Date.new(2026, 11, 30), tuesday)).to eq([BigDecimal("30.00"), 0])
    end

    it "never counts another organization's payments" do
      other = build_work_order_scenario
      work_order = open_work_order(other)
      add_authorized_item(other, work_order, unit_price: "900.00")
      other_receivable = issue_receivable(other, work_order, "900", due_on: Date.new(2026, 12, 20))
      travel_to(tuesday_at(12)) { pay(other_receivable, "900.00") }
      paid("15.00", at: tuesday_at(9))

      expect(on_dashboard(finance, &:daily_receipts).sum(&:amount)).to eq(BigDecimal("15.00"))
    end

    it "is only available with finance permission and the finance module" do
      expect(on_dashboard(create(:membership, :owner, organization:), &:daily_receipts)).to be_present
      expect(on_dashboard(coordinator, &:daily_receipts)).to be_nil

      subscribe("profissional")

      expect(on_dashboard(finance, &:daily_receipts)).to be_nil
    end
  end
end

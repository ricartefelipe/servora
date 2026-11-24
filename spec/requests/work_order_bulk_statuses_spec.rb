# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Work order bulk status change" do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }

  def move(ids, to:, reason: nil, retorno: {})
    post work_orders_bulk_status_path,
      params: { work_order_ids: ids, status_change: { to:, reason: }, retorno: }
  end

  def statuses(*work_orders) = in_tenant(organization) { work_orders.map { |work_order| work_order.reload.status } }

  it "moves every selected order through WorkOrders::ChangeStatus" do
    first = open_work_order(scenario)
    second = open_work_order(scenario, title: "Câmara fria")
    sign_in_as(scenario[:coordinator])

    move([first.id, second.id], to: "in_progress", retorno: { situacao: "approved", q: "split" })

    expect(response).to redirect_to(work_orders_path(situacao: "approved", q: "split"))
    expect(flash[:notice]).to eq("2 ordens atualizadas para Em execução.")
    expect(statuses(first, second)).to eq(%w[in_progress in_progress])
    moved = in_tenant(organization) { WorkOrderTransition.where(work_order_id: [first.id, second.id]).pluck(:to_status) }
    expect(moved.count("in_progress")).to eq(2)
  end

  it "records one labelled audit event with the changed orders" do
    first = open_work_order(scenario)
    second = open_work_order(scenario, title: "Câmara fria")
    sign_in_as(scenario[:coordinator])

    move([first.id, second.id], to: "in_progress")

    event = in_tenant(organization) { AuditEvent.find_by!(action: "work_order.bulk_status_changed") }
    expect(event.changeset).to include("status" => "Em execução", "updated_numbers" => [first.number, second.number].sort)
    expect(event.metadata["work_order_ids"]).to contain_exactly(first.id, second.id)
    expect(event.actor_membership_id).to eq(scenario[:coordinator].id)
    expect(Audit::Labels.action(event.action)).to eq("Ordem de serviço · situação alterada em lote")
  end

  it "keeps the orders that changed when others are refused and lists the refusals" do
    movable = open_work_order(scenario)
    started = open_work_order(scenario, title: "Já iniciada")
    in_tenant(organization) { WorkOrders::Transition.new(work_order: started, to: "in_progress", actor: nil).call }
    sign_in_as(scenario[:coordinator])

    move([movable.id, started.id], to: "in_progress")

    expect(flash[:alert]).to eq(
      "1 ordem atualizada para Em execução; 1 não pôde ser alterada: #{started.number} (situação não permite)."
    )
    expect(statuses(movable, started)).to eq(%w[in_progress in_progress])
    expect(in_tenant(organization) { WorkOrderTransition.where(work_order_id: started.id, to_status: "in_progress").count })
      .to eq(1)
  end

  it "reports when no order could change" do
    started = open_work_order(scenario)
    in_tenant(organization) { WorkOrders::Transition.new(work_order: started, to: "in_progress", actor: nil).call }
    sign_in_as(scenario[:coordinator])

    move([started.id], to: "approved")

    expect(flash[:alert]).to eq("Nenhuma ordem foi alterada: #{started.number} (situação não permite).")
    expect(in_tenant(organization) { AuditEvent.where(action: "work_order.bulk_status_changed").count }).to eq(0)
  end

  it "requires a reason for the waiting states before touching any order" do
    work_order = open_work_order(scenario)
    in_tenant(organization) { WorkOrders::Transition.new(work_order:, to: "in_progress", actor: nil).call }
    sign_in_as(scenario[:coordinator])

    move([work_order.id], to: "waiting_parts", reason: "  ")
    expect(flash[:alert]).to eq("Informe o motivo da espera.")
    expect(statuses(work_order)).to eq(["in_progress"])

    move([work_order.id], to: "waiting_parts", reason: "Compressor encomendado")
    expect(flash[:notice]).to eq("1 ordem atualizada para Aguardando peças.")
    expect(in_tenant(organization) { work_order.transitions.find_by!(to_status: "waiting_parts").reason })
      .to eq("Compressor encomendado")
  end

  it "refuses targets outside the simple operational transitions" do
    work_order = open_work_order(scenario)
    sign_in_as(scenario[:coordinator])

    move([work_order.id], to: "completed")

    expect(flash[:alert]).to eq("Escolha uma situação válida.")
    expect(statuses(work_order)).to eq(["approved"])
  end

  it "ignores ids from another organization" do
    own = open_work_order(scenario)
    other_scenario = build_work_order_scenario
    foreign = open_work_order(other_scenario)
    sign_in_as(scenario[:coordinator])

    move([own.id, foreign.id], to: "scheduled")

    expect(flash[:notice]).to eq("1 ordem atualizada para Agendada.")
    expect(in_tenant(other_scenario[:organization]) { foreign.reload.status }).to eq("approved")
    expect(statuses(own)).to eq(["scheduled"])
  end

  it "authorizes each order: technicians only move the orders assigned to them" do
    assigned = open_work_order(scenario)
    unassigned = open_work_order(scenario, title: "De outra equipe")
    in_tenant(organization) { WorkOrders::Assign.new(work_order: assigned, membership: scenario[:technician]).call }
    sign_in_as(scenario[:technician])

    move([assigned.id, unassigned.id], to: "in_progress")

    expect(flash[:notice]).to eq("1 ordem atualizada para Em execução.")
    expect(statuses(assigned, unassigned)).to eq(%w[in_progress approved])
  end

  it "is forbidden to roles that cannot change work orders" do
    work_order = open_work_order(scenario)
    sign_in_as(create(:membership, :auditor, organization:))

    move([work_order.id], to: "in_progress")

    expect(response).to have_http_status(:forbidden)
    expect(statuses(work_order)).to eq(["approved"])
  end

  it "caps the batch size and asks for a selection" do
    work_order = open_work_order(scenario)
    sign_in_as(scenario[:coordinator])

    move([work_order.id] + Array.new(WorkOrders::BulkChangeStatus::MAX_ORDERS) { SecureRandom.uuid }, to: "scheduled")
    expect(flash[:alert]).to eq("Selecione no máximo 100 ordens por vez.")
    expect(statuses(work_order)).to eq(["approved"])

    move([], to: "scheduled")
    expect(flash[:alert]).to eq("Selecione ao menos uma ordem.")
    expect(response).to redirect_to(work_orders_path)
  end

  it "shows the selection controls only to roles that can change orders" do
    work_order = open_work_order(scenario)

    sign_in_as(scenario[:coordinator])
    get work_orders_path
    expect(response.body).to include("Selecionar #{work_order.number}", "Selecionar todas as ordens desta página", "Mover para")

    sign_in_as(create(:membership, :auditor, organization:))
    get work_orders_path
    expect(response.body).to include(work_order.number)
    expect(response.body).not_to include("Selecionar todas as ordens desta página", "Mover para")
  end
end

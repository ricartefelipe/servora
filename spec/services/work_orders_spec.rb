# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkOrders do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let!(:work_order) { open_work_order(scenario) }

  describe WorkOrders::Create do
    it "numbers the order, links equipment, copies the checklist and records the transition" do
      in_tenant(organization) do
        expect(work_order.number).to match(/\AOS-\d{4}-00001\z/)
        expect(work_order.status).to eq("approved")
        expect(work_order.equipment).to eq([scenario[:equipment]])
        expect(work_order.checklist_items.map(&:label)).to eq(["Medir pressão de sucção", "Limpar filtros", "Observações"])
        expect(work_order.transitions.map(&:to_status)).to eq(["approved"])
        expect(OutboxEvent.pluck(:event_type)).to include("work_order.created")
      end
    end

    it "keeps the checklist even if the service type changes later" do
      in_tenant(organization) { scenario[:service_type].checklist_items.first.update!(label: "Outro") }

      expect(in_tenant(organization) { work_order.checklist_items.first.label }).to eq("Medir pressão de sucção")
    end

    it "refuses equipment of another customer at the database level" do
      foreign = create(:equipment, location: create(:service_location, customer: create(:customer, organization:)))

      expect do
        as_member(scenario[:coordinator]) do
          described_class.new(organization:, actor: scenario[:coordinator], equipment_ids: [foreign.id],
            attributes: { title: "x", problem_description: "y", origin: "phone", customer_id: scenario[:customer].id,
                          service_location_id: scenario[:location].id }).call
        end
      end.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  describe WorkOrders::Transition do
    it "rejects invalid transitions" do
      expect do
        in_tenant(organization) { described_class.new(work_order:, to: "completed", actor: scenario[:coordinator]).call }
      end.to raise_error(WorkOrders::Transition::InvalidTransition, /Aprovada para Concluída/)
    end
  end

  describe WorkOrders::Complete do
    it "refuses completion without the required checklist, diagnosis and solution" do
      in_tenant(organization) { WorkOrders::Transition.new(work_order:, to: "in_progress", actor: scenario[:coordinator]).call }

      expect { as_member(scenario[:coordinator]) { described_class.new(work_order:, actor: scenario[:coordinator]).call } }
        .to raise_error(described_class::RequirementsMissing, /Medir pressão de sucção, Limpar filtros.*diagnóstico.*solução/)
    end

    it "completes, stores report version 1 and publishes the event" do
      ready_to_complete!(scenario, work_order)

      as_member(scenario[:coordinator]) { described_class.new(work_order: work_order.reload, actor: scenario[:coordinator]).call }

      in_tenant(organization) do
        report = work_order.reports.sole
        expect(work_order.reload).to have_attributes(status: "completed")
        expect(report.data["checklist"].pluck("response")).to eq(["68", "sim", ""])
        expect(report.content_digest).to eq(Quotes::ContentDigest.call(report.data))
        expect(OutboxEvent.pluck(:event_type)).to include("work_order.completed")
      end
    end

    it "blocks completion while additional items await authorization" do
      ready_to_complete!(scenario, work_order)
      item = as_member(scenario[:coordinator]) do
        WorkOrders::AddItem.new(work_order:, actor: scenario[:coordinator], quantity: 1, description: "Troca de capacitor",
          unit_price: "120").call
      end

      expect do
        as_member(scenario[:coordinator]) do
          described_class.new(work_order: work_order.reload, actor: scenario[:coordinator]).call
        end
      end
        .to raise_error(described_class::RequirementsMissing, /serviços adicionais/)

      as_member(scenario[:coordinator]) do
        WorkOrders::DecideItem.new(item:, decision: "authorized", actor: scenario[:coordinator], contact: scenario[:approver],
          channel: "phone", note: "Autorizado por telefone").call
        described_class.new(work_order: work_order.reload, actor: scenario[:coordinator]).call
      end
      expect(in_tenant(organization) { work_order.reload.status }).to eq("completed")
    end
  end

  describe WorkOrders::Reopen do
    it "reopens with a reason and keeps the previous report" do
      ready_to_complete!(scenario, work_order)
      as_member(scenario[:coordinator]) { WorkOrders::Complete.new(work_order: work_order.reload, actor: scenario[:coordinator]).call }

      expect do
        as_member(scenario[:coordinator]) do
          described_class.new(work_order:, actor: scenario[:coordinator], reason: "").call
        end
      end
        .to raise_error(described_class::ReasonRequired)
      as_member(scenario[:coordinator]) do
        described_class.new(work_order:, actor: scenario[:coordinator], reason: "Vazamento voltou").call
      end
      in_tenant(organization) { WorkOrders::Transition.new(work_order: work_order.reload, to: "in_progress", actor: nil).call }
      as_member(scenario[:coordinator]) { WorkOrders::Complete.new(work_order: work_order.reload, actor: scenario[:coordinator]).call }

      in_tenant(organization) do
        expect(work_order.reload).to have_attributes(status: "completed", reopened_count: 1)
        expect(work_order.reports.pluck(:version_number)).to eq([2, 1])
      end
    end
  end

  describe WorkOrders::Cancel do
    it "requires a reason and cannot cancel a completed order" do
      expect do
        as_member(scenario[:coordinator]) do
          described_class.new(work_order:, actor: scenario[:coordinator], reason: " ").call
        end
      end
        .to raise_error(described_class::ReasonRequired)

      as_member(scenario[:coordinator]) do
        described_class.new(work_order:, actor: scenario[:coordinator], reason: "Cliente desistiu").call
      end
      expect(in_tenant(organization) do
        work_order.reload
      end).to have_attributes(status: "canceled", cancel_reason: "Cliente desistiu")
    end
  end

  describe WorkOrders::ChangeStatus do
    it "requires a reason to wait for parts or for the customer" do
      in_tenant(organization) { WorkOrders::Transition.new(work_order:, to: "in_progress", actor: nil).call }

      expect { in_tenant(organization) { described_class.new(work_order:, to: "waiting_parts", actor: nil).call } }
        .to raise_error(described_class::ReasonRequired)
      in_tenant(organization) do
        described_class.new(work_order:, to: "waiting_parts", actor: nil, reason: "Compressor em falta").call
      end
      expect { in_tenant(organization) { described_class.new(work_order:, to: "completed", actor: nil).call } }
        .to raise_error(WorkOrders::Transition::InvalidTransition)
    end
  end

  describe WorkOrders::AnswerChecklist do
    it "detects concurrent answers through the version" do
      item = in_tenant(organization) { work_order.checklist_items.find_by!(response_kind: "check") }
      seen_version = item.lock_version
      in_tenant(organization) { described_class.new(item:, response: "sim", actor: scenario[:technician]).call }

      expect do
        in_tenant(organization) do
          described_class.new(item: item.reload, response: "nao", actor: scenario[:technician],
            expected_version: seen_version).call
        end
      end.to raise_error(described_class::Conflict, /alterado por outra pessoa/)
    end

    it "validates the response format by kind" do
      item = in_tenant(organization) { work_order.checklist_items.find_by!(response_kind: "number") }

      expect { in_tenant(organization) { described_class.new(item:, response: "muito", actor: nil).call } }
        .to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe WorkOrders::DecideItem do
    it "refuses contacts that cannot authorize and repeated decisions" do
      item = as_member(scenario[:coordinator]) do
        WorkOrders::AddItem.new(work_order:, actor: scenario[:coordinator], quantity: 1, description: "Extra",
          unit_price: "10").call
      end
      follower = create(:customer_contact, customer: scenario[:customer], can_approve: false)

      expect do
        in_tenant(organization) do
          described_class.new(item:, decision: "authorized", actor: scenario[:coordinator], contact: follower,
            channel: "phone").call
        end
      end.to raise_error(described_class::DecisionRefused, /não pode autorizar/)
      in_tenant(organization) do
        described_class.new(item:, decision: "rejected", actor: scenario[:coordinator], contact: scenario[:approver],
          channel: "email").call
      end
      expect do
        in_tenant(organization) do
          described_class.new(item: item.reload, decision: "authorized", actor: scenario[:coordinator],
            contact: scenario[:approver],
            channel: "email").call
        end
      end.to raise_error(described_class::DecisionRefused, /já foi decidido/)
    end
  end
end

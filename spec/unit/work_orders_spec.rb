# frozen_string_literal: true

RSpec.describe WorkOrders do
  describe WorkOrders::States do
    it "does not complete without executing and allows authorized reopening" do
      expect(described_class.allowed?(:scheduled, :completed)).to be(false)
      expect(described_class.allowed?(:in_progress, :completed)).to be(true)
      expect(described_class.allowed?(:completed, :reopened)).to be(true)
      expect(described_class.allowed?(:completed, :canceled)).to be(false)
      expect(described_class.terminal?(:canceled)).to be(true)
    end

    it "lets waiting states return to execution or scheduling" do
      expect(described_class.targets(:waiting_parts)).to contain_exactly("scheduled", "in_progress", "canceled")
      expect(WorkOrders::LABELS.keys).to match_array(described_class.states)
    end
  end

  describe WorkOrders::CompletionRequirements do
    let(:checklist) do
      [WorkOrders::CompletionRequirements::Checklist.new("Pressão de sucção", true, ""),
       WorkOrders::CompletionRequirements::Checklist.new("Limpeza dos filtros", true, "sim"),
       WorkOrders::CompletionRequirements::Checklist.new("Foto opcional", false, nil)]
    end

    it "lists every missing requirement" do
      missing = described_class.missing(checklist:, diagnosis: " ", solution: nil, visits_in_progress: 1,
        pending_authorizations: 2)

      expect(missing).to eq([
                              "Responder os itens obrigatórios do checklist: Pressão de sucção", "Registrar o diagnóstico",
                              "Registrar a solução aplicada", "Finalizar a visita em andamento",
                              "Decidir os serviços adicionais pendentes de autorização"
                            ])
    end

    it "is empty when everything is in place" do
      answered = [checklist.first.with(response: "70 psi"), *checklist.drop(1)]

      expect(described_class.missing(checklist: answered, diagnosis: "Filtro obstruído", solution: "Limpeza",
        visits_in_progress: 0,
        pending_authorizations: 0)).to be_empty
    end
  end
end

# frozen_string_literal: true

module Documents
  # Execution report rendered from the frozen data of a report version. Each
  # completion keeps its own version; reopening never rewrites earlier ones.
  class ExecutionReport < Base
    def initialize(report, organization:)
      @data = report.data
      super(title: "Relatório de execução", organization:,
            reference: "#{@data.dig("work_order", "number")} · versão #{report.version_number}", digest: report.content_digest)
    end

    private

    def body
      service_details
      equipment
      narrative
      checklist
      services
      pdf.move_down 10
      pdf.text safe("Relatório técnico do atendimento. Não é nota fiscal."), size: 8, color: MUTED
    end

    def service_details
      order = @data["work_order"]
      location = @data["location"]
      section("Atendimento")
      field("Ordem", "#{order["number"]} — #{order["title"]}")
      field("Cliente", @data["customer"].values_at("name", "document").compact_blank.join(" · "))
      field("Local", "#{location["name"]} — #{location.values_at("address", "city").join(", ")}")
      dates_and_team(order)
    end

    def dates_and_team(order)
      field("Solicitada em", date(order["requested_at"]))
      field("Concluída em", date(order["completed_at"]))
      field("Técnicos", Array(@data["technicians"]).join(", "))
    end

    def equipment
      list = Array(@data["equipment"])
      return if list.empty?

      section("Equipamentos")
      list.each { |item| paragraph("• #{item["title"]}#{" — série #{item["serial_number"]}" if item["serial_number"].present?}") }
    end

    def narrative
      section("Problema relatado")
      paragraph(@data["problem"])
      section("Diagnóstico")
      paragraph(@data["diagnosis"])
      section("Solução aplicada")
      paragraph(@data["solution"])
    end

    def checklist
      items = Array(@data["checklist"])
      return if items.empty?

      section("Checklist")
      table(%w[Item Resposta], items.map { |item| [item["label"], item["response"].presence || "—"] }, widths: [330, 169])
    end

    def services
      items = Array(@data["services"])
      return if items.empty?

      section("Serviços e materiais")
      table(%w[Descrição Quantidade], items.map { |item| [item["description"], "#{quantity(item["quantity"])} #{item["unit"]}"] },
        widths: [380, 119], align: %i[left right])
    end
  end
end

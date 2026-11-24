# frozen_string_literal: true

module Documents
  # Commercial proposal rendered from the frozen snapshot of a sent quote
  # version: what the customer received and approved, never the current data.
  class QuoteProposal < Base
    def initialize(version)
      @snapshot = version.snapshot
      @status = version.status_label
      quote = @snapshot["quote"]
      super(title: "Proposta comercial", organization: @snapshot["organization"],
            reference: "#{quote["number"]} · versão #{quote["version"]}", digest: version.content_digest)
    end

    private

    def body
      customer = @snapshot["customer"]
      location = @snapshot["location"]
      section("Cliente")
      field("Nome", [customer["name"], customer["trade_name"].presence].compact.join(" — "))
      field("Documento", customer["document"])
      field("Local", "#{location["name"]} — #{location["address"]}, #{location["city"]}")
      section(@snapshot.dig("quote", "title"))
      items
      totals
      terms
    end

    def items
      rows = @snapshot["items"].map do |item|
        [item["description"], "#{quantity(item["quantity"])} #{item["unit"]}", money(item["unit_price"]),
         item["discount"].to_d.positive? ? money(item["discount"]) : "—", money(item["total"])]
      end
      table(["Descrição", "Quantidade", "Valor unitário", "Desconto", "Total"], rows, widths: [215, 70, 80, 64, 70],
        align: %i[left right right right right])
    end

    def totals
      totals = @snapshot["totals"]
      pdf.move_down 6
      [["Subtotal", totals["subtotal"]], ["Desconto", totals["discount"]], ["Total", totals["total"]]].each do |label, value|
        pdf.text safe("#{label}: #{money(value)}"), align: :right, size: label == "Total" ? 12 : 9.5,
          style: label == "Total" ? :bold : :normal
      end
    end

    def terms
      terms = @snapshot["terms"]
      section("Condições")
      field("Validade", date(terms["valid_until"]))
      field("Pagamento", terms["payment_terms"])
      paragraph(terms["notes"])
      field("Situação desta versão", @status)
      pdf.move_down 10
      pdf.text safe("Esta proposta não é nota fiscal. Valores em reais (BRL)."), size: 8, color: MUTED
    end
  end
end

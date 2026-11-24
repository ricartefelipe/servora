# frozen_string_literal: true

require "prawn"

module Documents
  # A4 document with the organization header, page numbers and a footer that
  # identifies the source version (content digest). Text is restricted to the
  # Windows-1252 repertoire of Prawn's built-in fonts, which covers Portuguese.
  class Base
    INK = "1F2937"
    MUTED = "6B7280"
    BRAND = "0F766E"
    LINE = "E5E7EB"

    def initialize(title:, organization:, reference:, digest:)
      @title = title
      @organization = organization
      @reference = reference
      @digest = digest
    end

    def render
      @pdf = Prawn::Document.new(page_size: "A4", margin: [64, 48, 72, 48],
        info: { Title: safe("#{@title} #{@reference}"), Creator: "Servora", Producer: "Servora" })
      @pdf.font("Helvetica", size: 10)
      @pdf.fill_color(INK)
      header
      body
      footer
      @pdf.render
    end

    private

    attr_reader :pdf

    def body = raise(NotImplementedError)

    def header
      pdf.text safe(@organization["name"]), size: 15, style: :bold, color: BRAND
      pdf.text safe(organization_details), size: 8, color: MUTED
      pdf.move_down 14
      pdf.text safe(@title), size: 18, style: :bold
      pdf.text safe(@reference), size: 10, color: MUTED
      pdf.move_down 12
      rule
    end

    def organization_details
      document = @organization["document"].to_s
      label = document.gsub(/\W/, "").size == 11 ? "CPF" : "CNPJ"
      [@organization["legal_name"], ("#{label} #{document}" if document.present?)].compact_blank.join(" · ")
    end

    def footer
      pdf.repeat(:all) do
        pdf.bounding_box([0, -18], width: pdf.bounds.width, height: 30) do
          pdf.text safe("Documento gerado a partir da versão registrada · verificação #{@digest.to_s.first(16)}"), size: 7,
            color: MUTED
        end
      end
      pdf.number_pages "Página <page> de <total>", at: [pdf.bounds.right - 120, -18], width: 120, align: :right, size: 7,
        color: MUTED
    end

    def section(title)
      pdf.move_down 14
      pdf.text safe(title), size: 11, style: :bold, color: BRAND
      pdf.move_down 4
    end

    def field(label, value)
      return if value.blank?

      pdf.formatted_text [{ text: safe("#{label}: "), styles: [:bold] }, { text: safe(value.to_s) }], size: 9.5
    end

    def paragraph(text)
      pdf.text safe(text.to_s), size: 9.5, leading: 2 if text.present?
    end

    # Simple table without external dependencies: fixed column widths, wrapped
    # cells, header repeated on page breaks.
    def table(headers, rows, widths:, align: [])
      draw_row(headers, widths, align, bold: true)
      rows.each do |row|
        pdf.start_new_page && draw_row(headers, widths, align, bold: true) if pdf.cursor < 40
        draw_row(row, widths, align)
      end
    end

    def draw_row(cells, widths, align, bold: false)
      style = bold ? :bold : :normal
      texts = cells.map { |cell| safe(cell.to_s) }
      height = row_height(texts, widths, style)
      top = pdf.cursor
      texts.each_with_index.reduce(0) do |x, (text, index)|
        pdf.text_box text, at: [x + 3, top - 4], width: widths[index] - 6, height:, size: 9, style:, align: align[index] || :left
        x + widths[index]
      end
      pdf.move_down height
      rule
    end

    def row_height(texts, widths, style)
      texts.each_with_index.map { |text, index| pdf.height_of(text, width: widths[index] - 6, size: 9, style:) }.max + 8
    end

    def rule
      pdf.stroke_color(LINE)
      pdf.stroke_horizontal_rule
      pdf.move_down 4
    end

    def money(value) = Pricing::Format.brl(BigDecimal(value.to_s))

    def quantity(value) = BigDecimal(value.to_s).to_s("F").delete_suffix(".0").tr(".", ",")

    def date(iso) = iso.present? ? I18n.l(Date.iso8601(iso.to_s[0, 10])) : nil

    def safe(text)
      text.to_s.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?").encode("UTF-8")
    end
  end
end

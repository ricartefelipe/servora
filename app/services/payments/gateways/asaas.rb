# frozen_string_literal: true

require "net/http"

module Payments
  module Gateways
    # Asaas REST API (v3). Only the sandbox is supported in this version; the
    # base URL comes from ASAAS_BASE_URL. Calls are never made inside database
    # transactions and always have connect/read timeouts.
    #
    # Our external_reference travels as `externalReference`, so a charge whose
    # response was lost can be found again (GET /payments?externalReference=…).
    class Asaas
      DEFAULT_BASE_URL = "https://api-sandbox.asaas.com/v3"
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 15
      BILLING_TYPES = { "pix" => "PIX", "boleto" => "BOLETO" }.freeze
      STATUS_MAP = {
        "PENDING" => "submitted", "OVERDUE" => "submitted", "AWAITING_RISK_ANALYSIS" => "submitted",
        "RECEIVED" => "confirmed", "CONFIRMED" => "confirmed", "RECEIVED_IN_CASH" => "confirmed",
        "REFUNDED" => "canceled", "REFUND_REQUESTED" => "canceled", "DELETED" => "canceled"
      }.freeze
      NOT_DELIVERED = [Net::OpenTimeout, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError].freeze
      MAYBE_DELIVERED = [Net::ReadTimeout, Net::WriteTimeout, EOFError, Errno::ECONNRESET, OpenSSL::SSL::SSLError].freeze

      def initialize(api_key:, base_url: ENV.fetch("ASAAS_BASE_URL", DEFAULT_BASE_URL))
        raise ArgumentError, "Asaas API key is required" if api_key.blank?

        @api_key = api_key
        @base_uri = URI(base_url.delete_suffix("/"))
      end

      def create_charge(charge, customer)
        body = request(:post, "/payments", {
          customer: customer_id(customer), billingType: BILLING_TYPES.fetch(charge.billing_type),
          value: charge.amount.to_s("F"), dueDate: charge.due_on.iso8601,
          description: "Servora #{charge.external_reference}", externalReference: charge.external_reference
        })
        remote(body)
      end

      def find_charge(charge)
        body = request(:get, "/payments?#{URI.encode_www_form(externalReference: charge.external_reference)}")
        found = Array(body["data"]).first
        found && remote(found)
      end

      INVOICE_STATUS = {
        "SCHEDULED" => "scheduled", "SYNCHRONIZED" => "scheduled", "AUTHORIZATION_PENDING" => "scheduled",
        "AUTHORIZED" => "authorized", "PROCESSING_CANCELLATION" => "canceling", "CANCELED" => "canceled",
        "CANCELLATION_DENIED" => "authorized", "ERROR" => "error"
      }.freeze

      # POST /invoices (linked to the provider payment when there is one, else
      # to the customer) followed by POST /invoices/{id}/authorize to issue now.
      def issue_invoice(invoice, customer, settings, charge)
        created = request(:post, "/invoices", invoice_payload(invoice, customer, settings, charge))
        remote_invoice(request(:post, "/invoices/#{URI.encode_www_form_component(created.fetch("id"))}/authorize"))
      end

      def find_invoice(invoice)
        body = request(:get, "/invoices?#{URI.encode_www_form(externalReference: invoice.external_reference)}")
        found = Array(body["data"]).first
        found && remote_invoice(found)
      end

      def cancel_invoice(invoice)
        remote_invoice(request(:post, "/invoices/#{URI.encode_www_form_component(invoice.external_id)}/cancel"))
      end

      # POST /payments/{id}/refund (full or partial). The response is the payment;
      # a 2xx means the provider accepted the refund.
      def refund_charge(charge, refund)
        body = request(:post, "/payments/#{URI.encode_www_form_component(charge.external_id)}/refund",
          { value: refund.amount.to_s("F"), description: "Estorno Servora #{refund.id}".first(500) })
        RemoteRefund.new(external_id: body["id"] || charge.external_id, status: "accepted")
      end

      def cancel_charge(charge)
        request(:delete, "/payments/#{URI.encode_www_form_component(charge.external_id)}")
        nil
      end

      private

      # Customers are matched by our customer id (externalReference) and
      # created when missing.
      def customer_id(customer)
        query = URI.encode_www_form(externalReference: customer.id)
        existing = Array(request(:get, "/customers?#{query}")["data"]).first
        return existing["id"] if existing

        document = customer.document.to_s.gsub(/[^0-9A-Za-z]/, "")
        raise Errors::Rejected, "Cadastre o CPF ou CNPJ do cliente para emitir cobranças." if document.blank?

        request(:post, "/customers", { name: customer.name, cpfCnpj: document, email: customer.email.presence,
                                       externalReference: customer.id }.compact)["id"]
      end

      def invoice_payload(invoice, customer, settings, charge)
        link = charge&.external_id ? { payment: charge.external_id } : { customer: customer_id(customer) }
        link.merge(
          serviceDescription: invoice.description.first(2000), observations: "Servora #{invoice.external_reference}",
          value: invoice.amount.to_s("F"), deductions: 0, effectiveDate: Time.zone.today.iso8601,
          externalReference: invoice.external_reference, municipalServiceCode: settings.municipal_service_code,
          municipalServiceName: settings.municipal_service_name,
          taxes: { retainIss: settings.retain_iss, iss: settings.iss_rate.to_s("F"), cofins: 0, csll: 0, inss: 0, ir: 0, pis: 0 }
        )
      end

      def remote_invoice(body)
        RemoteInvoice.new(external_id: body.fetch("id"), status: INVOICE_STATUS.fetch(body["status"], "scheduled"),
          number: body["number"], verification_code: body["validationCode"], pdf_url: body["pdfUrl"], xml_url: body["xmlUrl"],
          message: body["statusDescription"])
      end

      def remote(body)
        RemoteCharge.new(
          external_id: body.fetch("id"), status: STATUS_MAP.fetch(body["status"], "submitted"),
          payment_url: body["invoiceUrl"] || body["bankSlipUrl"],
          paid_at: paid_at(body),
          amount: (Pricing::Amount.money(body["value"].to_s) if body["value"])
        )
      end

      def paid_at(body)
        date = body["paymentDate"] || body["clientPaymentDate"]
        date && Time.zone.parse(date)
      end

      def request(verb, path, payload = nil)
        uri = URI("#{@base_uri}#{path}")
        operation = "#{verb} #{path.split("?").first.gsub(%r{/[\w-]{8,}\z}, "/:id")}"
        response = Servora::Metrics.measure_integration("asaas", operation) { http(uri).request(build(verb, uri, payload)) }
        handle(response)
      rescue *NOT_DELIVERED => e
        raise Errors::Unavailable, "Provedor indisponível: #{e.class.name}"
      rescue *MAYBE_DELIVERED => e
        raise Errors::AmbiguousResponse, "Resposta do provedor não recebida: #{e.class.name}"
      end

      def http(uri)
        Net::HTTP.new(uri.host, uri.port).tap do |http|
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = OPEN_TIMEOUT
          http.read_timeout = READ_TIMEOUT
          http.write_timeout = READ_TIMEOUT
        end
      end

      def build(verb, uri, payload)
        request = { get: Net::HTTP::Get, post: Net::HTTP::Post, delete: Net::HTTP::Delete }.fetch(verb).new(uri)
        request["access_token"] = @api_key
        request["Accept"] = "application/json"
        request["User-Agent"] = "Servora"
        if payload
          request["Content-Type"] = "application/json"
          request.body = JSON.generate(payload)
        end
        request
      end

      def handle(response)
        code = response.code.to_i
        body = parse(response.body)
        return body if code.between?(200, 299)
        raise Errors::Unavailable, "Limite de requisições do provedor atingido." if code == 429
        raise Errors::AmbiguousResponse, "Provedor respondeu #{code}" if code >= 500
        raise Errors::Rejected, "Credencial do Asaas recusada." if code == 401

        message = Array(body["errors"]).filter_map { |error| error["description"] }.join(" ").presence
        raise Errors::Rejected, message || "Requisição recusada pelo provedor (#{code})."
      end

      def parse(text)
        text.present? ? JSON.parse(text) : {}
      rescue JSON::ParserError
        {}
      end
    end
  end
end

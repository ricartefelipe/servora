# frozen_string_literal: true

require "ipaddr"
require "resolv"

module Webhooks
  # SSRF protection for outbound webhooks: HTTPS only, standard port, no
  # credentials in the URL, and every resolved address must be public. The
  # delivery connects to the address validated here (no second DNS lookup).
  module SafeUrl
    class Unsafe < StandardError; end

    BLOCKED = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16
      198.18.0.0/15 224.0.0.0/4 240.0.0.0/4 ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8 ::ffff:0:0/96
    ].map { |range| IPAddr.new(range) }.freeze

    Target = Data.define(:uri, :address)

    module_function

    def check!(url, resolver: Resolv)
      uri = parse!(url)
      addresses = resolver.getaddresses(uri.host)
      raise Unsafe, "o endereço não pôde ser resolvido" if addresses.empty?

      public_addresses = addresses.reject { |address| blocked?(address) }
      raise Unsafe, "o endereço aponta para uma rede interna" unless public_addresses.size == addresses.size

      Target.new(uri:, address: public_addresses.first)
    end

    def parse!(url)
      uri = URI.parse(url.to_s.strip)
      raise Unsafe, "use uma URL https" unless uri.is_a?(URI::HTTPS) && uri.host.present?
      raise Unsafe, "não inclua usuário ou senha na URL" if uri.userinfo
      raise Unsafe, "use a porta padrão 443" unless uri.port == 443

      uri
    rescue URI::InvalidURIError
      raise Unsafe, "URL inválida"
    end

    def blocked?(address)
      ip = IPAddr.new(address)
      BLOCKED.any? { |range| range.include?(ip) }
    rescue IPAddr::InvalidAddressError
      true
    end
  end
end

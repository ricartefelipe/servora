# frozen_string_literal: true

# Readable description of a signed-in device from its User-Agent header, for the
# account security page. Only the browser family and the operating system are
# shown; the full header stays available as a tooltip.
module SessionsHelper
  BROWSERS = [[%r{Edg/}, "Edge"], [%r{OPR/|Opera}, "Opera"], [%r{Firefox/}, "Firefox"], [%r{Chrome/}, "Chrome"],
              [%r{Safari/}, "Safari"]].freeze
  SYSTEMS = [[/Android/, "Android"], [/iPhone|iPad|iOS/, "iOS"], [/Windows/, "Windows"], [/Mac OS X|Macintosh/, "macOS"],
             [/CrOS/, "ChromeOS"], [/Linux/, "Linux"]].freeze
  MOBILE = /Mobile|Android|iPhone|iPad/

  def session_device(user_agent)
    agent = user_agent.to_s
    return ["Navegador desconhecido", :monitor] if agent.blank?

    label = [first_match(BROWSERS, agent) || "Navegador", first_match(SYSTEMS, agent)].compact.join(" · ")
    [label, MOBILE.match?(agent) ? :device : :monitor]
  end

  private

  def first_match(table, agent) = table.find { |pattern, _| pattern.match?(agent) }&.last
end

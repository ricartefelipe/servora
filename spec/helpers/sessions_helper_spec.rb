# frozen_string_literal: true

require "rails_helper"

RSpec.describe SessionsHelper do
  it "names the browser and the operating system of desktop sessions" do
    agent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"

    expect(helper.session_device(agent)).to eq(["Chrome · Linux", :monitor])
  end

  it "recognises mobile browsers" do
    agent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile Safari/604.1"

    expect(helper.session_device(agent)).to eq(["Safari · iOS", :device])
  end

  it "prefers Edge over the Chrome token it also carries" do
    agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0 Safari/537.36 Edg/131.0"

    expect(helper.session_device(agent)).to eq(["Edge · Windows", :monitor])
  end

  it "falls back when the header is missing" do
    expect(helper.session_device(nil)).to eq(["Navegador desconhecido", :monitor])
  end
end

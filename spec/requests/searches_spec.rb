# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Quick search" do
  let(:frame_headers) { { "Turbo-Frame" => "command-palette-results" } }
  let(:records) { seed_search_records(create(:organization)) }

  # One record of each kind, all reachable with the word "Horizonte" (titles or
  # customer name) and by their own identifiers.
  def seed_search_records(organization)
    scenario = build_work_order_scenario(organization:)
    in_tenant(organization) do
      scenario[:customer].update!(name: "Refrigeração Horizonte Ltda.", document: "11222333000181",
        email: "compras@horizonte.test")
      scenario[:equipment].update!(serial_number: "HZ-7788", asset_tag: "PAT-0042")
    end
    work_order = open_work_order(scenario, title: "Compressor Horizonte sem partida")
    quote = create_quote({ organization:, author: create(:membership, :attendant, organization:),
                           customer: scenario[:customer], location: scenario[:location] })
    scenario.merge(work_order:, quote:)
  end

  def search(term, headers: frame_headers)
    get search_path, params: { q: term }, headers:
  end

  # Group label => hrefs of its options, in the order rendered.
  def results
    response.parsed_body.css('[role="listbox"] [role="group"]').to_h do |group|
      [group.at_css('[role="presentation"]').text.strip, group.css('[role="option"]').pluck("href")]
    end
  end

  it "requires a signed-in user" do
    search("Horizonte")

    expect(response).to redirect_to(new_user_session_path)
  end

  it "returns grouped results for office roles inside the palette frame" do
    sign_in_as(records[:coordinator])

    search("horizonte")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<turbo-frame id="command-palette-results"')
    expect(response.body).not_to include("<html")
    expect(results).to eq(
      "Ordens de serviço" => [work_order_path(records[:work_order])],
      "Clientes" => [customer_path(records[:customer])],
      "Equipamentos" => [equipment_path(records[:equipment])]
    )
    expect(response.body).to include(records[:work_order].number, "11.222.333/0001-81", "HZ-7788")
  end

  it "finds each kind by its own identifiers" do
    sign_in_as(records[:coordinator])

    {
      records[:work_order].number => "Ordens de serviço", "11.222.333/0001-81" => "Clientes",
      "compras@horizonte" => "Clientes", "hz-7788" => "Equipamentos", "PAT-0042" => "Equipamentos",
      records[:quote].number => "Orçamentos", "climatização" => "Orçamentos"
    }.each do |term, group|
      search(term)
      expect(results.keys).to include(group), "expected #{term.inspect} to find #{group}"
    end
  end

  it "keeps at most five results per group" do
    organization = records[:organization]
    6.times { |index| create(:customer, organization:, name: "Horizonte Filial #{index}") }
    sign_in_as(records[:coordinator])

    search("Horizonte")

    expect(results["Clientes"].size).to eq(5)
  end

  it "offers only the groups the member may open" do
    in_tenant(records[:organization]) do
      WorkOrders::Assign.new(work_order: records[:work_order], membership: records[:technician]).call
    end
    unassigned = open_work_order(records, title: "Horizonte: vazamento na casa de máquinas")

    sign_in_as(records[:technician])
    search("Horizonte")
    expect(results).to eq(
      "Ordens de serviço" => [work_order_path(records[:work_order])],
      "Equipamentos" => [equipment_path(records[:equipment])]
    )
    expect(response.body).not_to include(unassigned.number)

    sign_in_as(create(:membership, :finance, organization: records[:organization]))
    search("Horizonte")
    expect(results.keys).to eq(["Ordens de serviço", "Clientes"])
  end

  it "never returns records from another organization, even on exact matches" do
    other = seed_search_records(create(:organization))
    sign_in_as(records[:coordinator])

    [records[:work_order].number, records[:quote].number, "Horizonte", "HZ-7788", "11222333000181"].each do |term|
      search(term)
      hrefs = results.values.flatten
      expect(hrefs).not_to be_empty
      expect(hrefs).not_to include(work_order_path(other[:work_order]), customer_path(other[:customer]),
        equipment_path(other[:equipment]), quote_path(other[:quote]))
    end
    expect(other[:work_order].number).to eq(records[:work_order].number)
  end

  it "ignores queries shorter than two characters" do
    sign_in_as(records[:coordinator])

    ["H", " h ", ""].each do |term|
      search(term)
      expect(response).to have_http_status(:ok)
      expect(results).to be_empty
      expect(response.body).to include("Digite ao menos 2 caracteres")
    end
  end

  it "escapes the term and binds it as a parameter" do
    sign_in_as(records[:coordinator])

    search(%(<img src=x onerror="alert(1)">))
    expect(response.body).to include("Nenhum resultado para “&lt;img src=x onerror=&quot;alert(1)&quot;&gt;”")
    expect(response.body).not_to include("<img src=x")

    search("' OR 1=1 --")
    expect(results).to be_empty

    search("100%")
    expect(results).to be_empty
  end

  it "renders a regular page with plain links outside the palette" do
    sign_in_as(records[:coordinator])

    search("Horizonte", headers: {})

    expect(response).to have_http_status(:ok)
    page = response.parsed_body
    expect(page.at_css("h1").text).to eq("Busca")
    expect(page.at_css('[role="option"]')).to be_nil
    expect(page.css("main ul a").pluck("href")).to include(customer_path(records[:customer]))
  end
end

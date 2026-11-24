# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Portuguese inflections" do # rubocop:disable RSpec/DescribeClass -- configuration behavior
  it "pluralizes interface words in pt-BR" do
    words = %w[dia minuto técnico local mês item ordem visita mulher papel anzol]
    expect(words.map { |word| word.pluralize(:"pt-BR") })
      .to eq(%w[dias minutos técnicos locais meses itens ordens visitas mulheres papéis anzóis])
  end

  it "is used by the pluralize helper" do
    expect(ApplicationController.helpers.pluralize(5, "dia")).to eq("5 dias")
    expect(ApplicationController.helpers.pluralize(1, "dia")).to eq("1 dia")
  end
end

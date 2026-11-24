# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.plural /^(ox)$/i, "\\1en"
#   inflect.singular /^(ox)en/i, "\\1"
#   inflect.irregular "person", "people"
#   inflect.uncountable %w( fish sheep )
# end

# These inflection rules are supported but not enabled by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.acronym "RESTful"
# end

# Portuguese plural rules for user-facing text (pluralize in pt-BR views).
# Covers the regular cases used by the interface; irregular words are listed.
ActiveSupport::Inflector.inflections(:"pt-BR") do |inflect|
  inflect.plural(/$/, "s")
  inflect.plural(/s$/i, "s")
  inflect.plural(/([rz])$/i, '\1es')
  inflect.plural(/al$/i, "ais")
  inflect.plural(/el$/i, "éis")
  inflect.plural(/ol$/i, "óis")
  inflect.plural(/ul$/i, "uis")
  inflect.plural(/il$/i, "is")
  inflect.plural(/m$/i, "ns")
  inflect.plural(/ão$/i, "ões")
  inflect.irregular("mês", "meses")
  inflect.irregular("local", "locais")
end

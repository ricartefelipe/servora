# Parameters filtered from logs, error reports and inspected records. Matching
# is partial ("token" also filters "access_token"). Audit trails apply their own
# redaction (see AuditTrail::Redactor).
Rails.application.config.filter_parameters += %i[
  passw email secret token _key crypt salt certificate otp ssn cvv cvc
  card_number api_key authorization signature document cpf cnpj
]
# Search terms often carry documents or e-mails. Anchored so that other keys
# containing "q" (quantity, quote_id) stay visible.
Rails.application.config.filter_parameters += [/\Aq\z/]

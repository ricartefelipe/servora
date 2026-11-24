# Cookie session: HttpOnly always, Secure in production, SameSite=Lax so that
# links arriving from e-mail keep working while cross-site POSTs carry no session.
Rails.application.config.session_store :cookie_store,
  key: "_servora_session",
  httponly: true,
  secure: Rails.env.production?,
  same_site: :lax,
  expire_after: 12.hours

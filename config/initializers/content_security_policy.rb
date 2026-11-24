# Content Security Policy: only same-origin resources, no inline scripts or
# styles without a nonce, no framing. Turbo reads the nonce from csp_meta_tag.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.font_src :self, :data
    policy.img_src :self, :data, :blob
    policy.media_src :self, :blob
    policy.object_src :none
    policy.script_src :self
    policy.style_src :self
    policy.connect_src :self
    policy.worker_src :self
    policy.manifest_src :self
    policy.frame_src :none
    policy.frame_ancestors :none
    policy.form_action :self
  end

  # A nonce stable for the session keeps Turbo Drive navigations working while
  # still forbidding injected inline code.
  config.content_security_policy_nonce_generator = lambda { |request|
    request.session.id.to_s.presence || SecureRandom.base64(16)
  }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end

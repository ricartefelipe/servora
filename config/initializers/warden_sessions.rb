# Server-side session registry (see Authentication::SessionTracker). These are
# the extension points documented by Warden/Devise, not patches. Constants are
# resolved when each hook runs, so code reloading keeps working.
Warden::Manager.after_set_user except: :fetch do |user, warden, options|
  next unless options[:scope] == :user && user.is_a?(User)

  Authentication::SessionTracker.new(warden:, scope: :user).start(user)
end

Warden::Manager.after_set_user only: :fetch do |user, warden, options|
  next unless options[:scope] == :user && user.is_a?(User)
  next if Authentication::SessionTracker.new(warden:, scope: :user).active_session?(user)

  warden.raw_session.clear
  throw :warden, scope: :user, message: :session_revoked
end

Warden::Manager.before_logout do |user, warden, options|
  next unless options[:scope] == :user && user.is_a?(User)

  Authentication::SessionTracker.new(warden:, scope: :user).finish(user)
end

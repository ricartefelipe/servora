# frozen_string_literal: true

class NotificationsController < TenantController
  def index
    authorize Notification
    @notifications = policy_scope(current_organization.notifications).recent_first.limit(50)
  end

  def update
    notification = policy_scope(current_organization.notifications).find(params.expect(:id))
    authorize notification
    notification.update!(read_at: Time.current) unless notification.read?
    redirect_to notification.path.presence || notifications_path
  end

  def read_all
    authorize Notification, :index?
    # Bulk state change with no validations or callbacks involved.
    policy_scope(current_organization.notifications).unread.update_all(read_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    redirect_to notifications_path, notice: "Todas as notificações foram marcadas como lidas."
  end
end

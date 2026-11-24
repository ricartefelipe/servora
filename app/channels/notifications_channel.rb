# frozen_string_literal: true

# Private notification stream of one membership. Beyond the signed stream name
# (which only proves the server generated it), the subscription is accepted
# only when the stream belongs to an active membership of the connected user.
class NotificationsChannel < Turbo::StreamsChannel
  def subscribed
    stream_name = verified_stream_name_from_params
    membership_id = membership_id_from(stream_name)
    return reject unless stream_name && membership_id && authorized?(membership_id)

    stream_from stream_name
  end

  private

  def membership_id_from(stream_name)
    gid = stream_name.to_s.split(":notifications").first
    located = GlobalID.parse(gid)
    located&.model_name == "Membership" ? located.model_id : nil
  end

  def authorized?(membership_id)
    Servora::Tenancy.with_context(user_id: current_user.id) do
      Membership.active.exists?(id: membership_id, user_id: current_user.id)
    end
  end
end

# frozen_string_literal: true

# External calls are always blocked; only the local browser driver may connect.
WebMock.disable_net_connect!(allow_localhost: true)

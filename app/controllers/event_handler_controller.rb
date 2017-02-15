class EventHandlerController < ApplicationController
  skip_before_action :verify_authenticity_token

  def github_event_handler
    GithubEventHandler.new(request, params.to_unsafe_h).handle
    head :ok
  end
end

module Tracebook
  class ApplicationController < ActionController::Base
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    protected

    def render_not_found
      render plain: "Not Found", status: :not_found
    end

    # Returns a display name for the current user from the host app.
    # Tries common patterns: email, name, id. Falls back to "Anonymous".
    #
    # @return [String]
    def current_tracebook_user_label
      return "Anonymous" unless respond_to?(:current_user, true) && current_user

      if current_user.respond_to?(:email) && current_user.email.present?
        current_user.email
      elsif current_user.respond_to?(:name) && current_user.name.present?
        current_user.name
      elsif current_user.respond_to?(:id)
        "User ##{current_user.id}"
      else
        "Anonymous"
      end
    end
  end
end

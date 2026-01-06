# frozen_string_literal: true

module Tracebook
  module ActorsHelper
    # Get human-readable display for an actor
    #
    # @param actor_type [String] Class name (e.g., "User", "VendorUser")
    # @param actor_id [Integer] Actor ID
    # @return [String] Display string for the actor
    def actor_display_name(actor_type, actor_id)
      fallback = "#{actor_type.to_s.demodulize} ##{actor_id}"
      return fallback if actor_type.blank? || actor_id.blank?

      klass = actor_type.safe_constantize
      return fallback unless klass

      record = klass.find_by(id: actor_id)
      return fallback unless record

      # Use configured lambda if provided
      if Tracebook.config.actor_display.respond_to?(:call)
        return Tracebook.config.actor_display.call(record).to_s
      end

      # Fallback: try common display methods
      %i[name email title display_name username].each do |method|
        return record.public_send(method).to_s if record.respond_to?(method)
      end

      fallback
    rescue StandardError
      fallback
    end

    # Session-level review badge showing aggregate status
    #
    # @param session [LlmSession] The session to display
    # @return [ActiveSupport::SafeBuffer] HTML badge
    def session_review_badge(session)
      case session.review_summary
      when :has_flagged
        content_tag(:span, "#{session.flagged_count} flagged", class: "tb-status tb-status-warning")
      when :has_pending
        content_tag(:span, "#{session.pending_count} pending", class: "tb-status tb-status-pending")
      else
        content_tag(:span, "approved", class: "tb-status tb-status-success")
      end
    end
  end
end

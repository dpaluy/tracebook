# frozen_string_literal: true

module Tracebook
  module ChatsHelper
    def cents_to_human(cents)
      number_to_currency(cents.to_f / 100.0)
    end

    def review_badge(review_state)
      css_class = case review_state.to_s
      when "approved" then "tb-status tb-status-success"
      when "flagged" then "tb-status tb-status-error"
      else "tb-status tb-status-pending"
      end
      content_tag(:span, review_state, class: css_class)
    end

    def actor_name(chat)
      actor = chat.try(:user)
      return "—" unless actor

      if Tracebook.config.actor_display
        Tracebook.config.actor_display.call(actor)
      else
        actor.try(:name) || actor.try(:email) || "#{actor.class.name}##{actor.id}"
      end
    end
  end
end

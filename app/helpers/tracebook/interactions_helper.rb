# frozen_string_literal: true

require "json"

module Tracebook
  module InteractionsHelper
    def payload_for(interaction, type)
      inline = interaction.public_send("#{type}_payload")
      return inline unless inline.nil? || (inline.respond_to?(:empty?) && inline.empty?)

      blob = interaction.public_send("#{type}_payload_blob")
      return nil unless blob

      raw = blob.download
      JSON.parse(raw)
    rescue JSON::ParserError
      raw
    end

    def formatted_payload(payload, fallback_text = nil)
      case payload
      when Hash, Array
        JSON.pretty_generate(payload)
      when String
        payload
      when nil
        fallback_text.to_s
      else
        JSON.pretty_generate(payload.as_json)
      end
    rescue JSON::GeneratorError, TypeError
      fallback_text ? fallback_text.to_s : payload.to_s
    end

    def status_badge(status)
      css_class = case status.to_s
      when "success" then "tb-status tb-status-success"
      when "error", "failed" then "tb-status tb-status-error"
      else "tb-status tb-status-pending"
      end
      content_tag(:span, status, class: css_class)
    end

    def review_badge(review_state)
      css_class = case review_state.to_s
      when "approved" then "tb-status tb-status-success"
      when "flagged" then "tb-status tb-status-warning"
      when "rejected" then "tb-status tb-status-error"
      else "tb-status tb-status-pending"
      end
      content_tag(:span, review_state, class: css_class)
    end

    def cents_to_human(cents)
      number_to_currency(cents.to_i / 100.0)
    end
  end
end

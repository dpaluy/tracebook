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

    def trackable_link(interaction)
      return "—" if interaction.trackable_id.blank?

      begin
        trackable_class = interaction.trackable_type.safe_constantize
        return fallback_trackable_display(interaction) unless trackable_class

        trackable = trackable_class.find_by(id: interaction.trackable_id)
        return content_tag(:span, "Deleted", class: "tb-muted") if trackable.nil?

        trackable_name = trackable.try(:name) || trackable.try(:title) || trackable.try(:email) ||
                         "#{interaction.trackable_type.demodulize}##{interaction.trackable_id}"

        begin
          link_to trackable_name, main_app.polymorphic_path(trackable), class: "tb-link"
        rescue ActionController::UrlGenerationError
          content_tag(:span, trackable_name, class: "tb-muted", title: "No route defined")
        end
      rescue StandardError => e
        Rails.logger.warn "[TraceBook] Failed to load trackable: #{e.message}"
        fallback_trackable_display(interaction)
      end
    end

    def fallback_trackable_display(interaction)
      type_name = interaction.trackable_type.to_s.demodulize
      content_tag(:span, "#{type_name}##{interaction.trackable_id}", class: "tb-muted")
    end

    def latency_display(latency_ms)
      return "—" if latency_ms.nil?

      if latency_ms >= 1000
        "#{(latency_ms / 1000.0).round(2)}s"
      else
        "#{latency_ms}ms"
      end
    end

    def token_breakdown(interaction)
      input = interaction.input_tokens || 0
      output = interaction.output_tokens || 0
      "#{number_with_delimiter(input)} / #{number_with_delimiter(output)}"
    end

    def trackable_type_options(trackable_types)
      trackable_types.map { |type| [type.demodulize, type] }
    end
  end
end

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
      else "tb-status tb-status-pending"
      end
      content_tag(:span, review_state, class: css_class)
    end

    def cents_to_human(cents)
      number_to_currency(cents.to_i / 100.0)
    end

    def actor_link(interaction)
      return "—" if interaction.actor_id.blank? || interaction.actor_type.blank?

      "#{interaction.actor_type.demodulize}##{interaction.actor_id}"
    end

    def latency_display(latency_ms)
      return "—" if latency_ms.nil?

      if latency_ms >= 1000
        "#{(latency_ms / 1000.0).round(2)}s"
      else
        "#{latency_ms}ms"
      end
    end

    def latency_class(latency_ms)
      return "" if latency_ms.nil?

      case latency_ms
      when 0..500 then "tb-latency-good"
      when 501..2000 then "tb-latency-warning"
      else "tb-latency-slow"
      end
    end

    def syntax_highlight_json(json_string)
      return "" if json_string.blank?

      # Escape HTML first
      escaped = ERB::Util.html_escape(json_string)

      # Apply syntax highlighting with spans
      escaped
        .gsub(/"([^"\\]|\\.)*":/, '<span class="tb-json-key">\0</span>')       # keys
        .gsub(/: "((?:[^"\\]|\\.)*)"/, ': <span class="tb-json-string">"\1"</span>')  # string values
        .gsub(/: (\d+\.?\d*)/, ': <span class="tb-json-number">\1</span>')     # numbers
        .gsub(/: (true|false)/, ': <span class="tb-json-boolean">\1</span>')   # booleans
        .gsub(/: (null)/, ': <span class="tb-json-null">\1</span>')            # null
        .gsub(/(\[REDACTED\])/, '<span class="tb-json-redacted">\1</span>')    # redacted
        .html_safe
    end

    def token_breakdown(interaction)
      input = interaction.input_tokens || 0
      output = interaction.output_tokens || 0
      "#{number_with_delimiter(input)} / #{number_with_delimiter(output)}"
    end

    def actor_type_options(actor_types)
      actor_types.map { |type| [ type.demodulize, type ] }
    end

    def fallback_actor_display(interaction)
      return "—" if interaction.actor_id.blank?

      type_display = interaction.actor_type&.demodulize || "Unknown"
      content_tag(:span, "#{type_display}##{interaction.actor_id}", class: "tb-muted")
    end

    def extract_messages(payload)
      return [] unless payload.is_a?(Hash)

      messages = payload["messages"] || payload[:messages] || []
      messages.map do |msg|
        {
          role: msg["role"] || msg[:role],
          content: msg["content"] || msg[:content]
        }
      end
    end

    def extract_response_content(payload)
      return nil unless payload.is_a?(Hash)

      payload["content"] || payload[:content] ||
        payload.dig("choices", 0, "message", "content") ||
        payload.dig("message", "content")
    end

    def truncate_message(content, length = 500)
      return "" if content.blank?

      content = content.to_s
      if content.length > length
        content[0...length] + "..."
      else
        content
      end
    end
  end
end

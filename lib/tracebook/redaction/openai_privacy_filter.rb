# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "ipaddr"

module Tracebook
  module Redaction
    class OpenAiPrivacyFilter
      DEFAULT_ENDPOINT = "http://127.0.0.1:8765"
      DEFAULT_TIMEOUT = 0.5
      DEFAULT_FAILURE_MODE = :fallback
      FAILURE_MODES = %i[fallback raise].freeze
      DEFAULT_LABEL_MAP = {
        "account_number" => "[ACCOUNT_NUMBER]",
        "private_address" => "[ADDRESS]",
        "private_email" => "[EMAIL]",
        "private_person" => "[PERSON]",
        "private_phone" => "[PHONE]",
        "private_url" => "[URL]",
        "private_date" => "[DATE]",
        "secret" => "[SECRET]"
      }.freeze

      class ClientError < StandardError; end

      Span = Data.define(:start, :end, :label)

      attr_reader :client, :failure_mode, :label_map

      def self.validate_failure_mode!(failure_mode)
        return if FAILURE_MODES.include?(failure_mode.to_sym)

        raise ConfigurationError, "Unknown OpenAI Privacy Filter failure mode: #{failure_mode.inspect}"
      rescue NoMethodError
        raise ConfigurationError, "Unknown OpenAI Privacy Filter failure mode: #{failure_mode.inspect}"
      end

      def initialize(
        endpoint: DEFAULT_ENDPOINT,
        timeout: DEFAULT_TIMEOUT,
        failure_mode: DEFAULT_FAILURE_MODE,
        label_map: DEFAULT_LABEL_MAP,
        client: nil
      )
        @client = client || Client.new(endpoint: endpoint, timeout: timeout)
        self.class.validate_failure_mode!(failure_mode)
        @failure_mode = failure_mode.to_sym
        @label_map = DEFAULT_LABEL_MAP.merge(normalize_label_map(label_map))
      end

      def call(text)
        return text unless text.is_a?(String)

        spans = spans_from(client.detect(text))
        return text if spans.empty?

        apply_spans(text, spans)
      rescue ClientError, JSON::ParserError, ArgumentError, TypeError, IOError, SystemCallError, SocketError,
        Timeout::Error, Net::OpenTimeout, Net::ReadTimeout, EOFError, URI::Error
        handle_failure(text, $!)
      end

      private

      def handle_failure(text, error)
        raise error if failure_mode == :raise

        log_failure(error)
        text
      end

      def log_failure(error)
        return unless defined?(Rails)

        Rails.logger.warn(
          "[Tracebook] OpenAI Privacy Filter redaction skipped: #{error.class}"
        )
      end

      def spans_from(response)
        data = response.is_a?(String) ? JSON.parse(response) : response
        spans = fetch_value(data, "detected_spans") || fetch_value(data, "spans") || []

        spans.filter_map do |span|
          normalize_span(span)
        end
      end

      def normalize_span(span)
        start_offset = Integer(fetch_value(span, "start"))
        end_offset = Integer(fetch_value(span, "end"))
        label = fetch_value(span, "label").to_s

        return unless label_map.key?(label)

        Span.new(start_offset, end_offset, label)
      rescue TypeError, ArgumentError
        nil
      end

      def apply_spans(text, spans)
        selected_spans = merge_adjacent_same_label_spans(select_non_overlapping_spans(text, spans))
        return text if selected_spans.empty?

        selected_spans.reverse_each.with_object(text.dup) do |span, result|
          result[span.start...span.end] = label_map.fetch(span.label)
        end
      end

      def merge_adjacent_same_label_spans(spans)
        spans.each_with_object([]) do |span, merged|
          last = merged.last
          if last && last.label == span.label && last.end == span.start
            merged[-1] = Span.new(last.start, span.end, last.label)
          else
            merged << span
          end
        end
      end

      def select_non_overlapping_spans(text, spans)
        last_end = 0
        spans
          .select { |span| valid_span?(text, span) }
          .sort_by { |span| [ span.start, -(span.end - span.start) ] }
          .each_with_object([]) do |span, selected|
            next if span.start < last_end

            selected << span
            last_end = span.end
          end
      end

      def valid_span?(text, span)
        span.start >= 0 &&
          span.end <= text.length &&
          span.start < span.end
      end

      def fetch_value(hash, key)
        hash[key] || hash[key.to_sym]
      end

      def normalize_label_map(label_map)
        label_map.to_h.transform_keys(&:to_s).transform_values(&:to_s)
      end

      class Client
        attr_reader :endpoint, :timeout

        LOOPBACK_IPV4 = IPAddr.new("127.0.0.0/8")
        LOOPBACK_IPV6 = IPAddr.new("::1")

        def self.validate_endpoint!(endpoint)
          uri = URI.parse(endpoint.to_s)
          validate_scheme!(uri)
          validate_host!(uri)
          uri
        rescue URI::Error => e
          raise ConfigurationError, "Invalid OpenAI Privacy Filter endpoint: #{e.message}"
        end

        def self.validate_scheme!(uri)
          return if %w[http https].include?(uri.scheme)

          raise ConfigurationError,
            "OpenAI Privacy Filter endpoint must use http or https"
        end

        def self.validate_host!(uri)
          return if loopback_host?(uri.host)

          raise ConfigurationError,
            "OpenAI Privacy Filter endpoint must be localhost or a loopback IP address"
        end

        def self.loopback_host?(host)
          return false if host.nil? || host.empty?
          return true if host == "localhost"

          ip = IPAddr.new(host)
          LOOPBACK_IPV4.include?(ip) || LOOPBACK_IPV6 == ip
        rescue IPAddr::InvalidAddressError
          false
        end

        def initialize(endpoint:, timeout:)
          @endpoint = endpoint
          @timeout = timeout
        end

        def detect(text)
          response = post_json({ text: text })
          raise ClientError, "sidecar returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

          JSON.parse(response.body)
        end

        private

        def post_json(payload)
          uri = endpoint_uri
          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          request.body = JSON.generate(payload)

          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: uri.scheme == "https",
            open_timeout: timeout,
            read_timeout: timeout
          ) do |http|
            http.request(request)
          end
        end

        def endpoint_uri
          uri = self.class.validate_endpoint!(endpoint)
          uri.path = "/redact" if uri.path.empty? || uri.path == "/"
          uri
        end
      end
    end
  end
end

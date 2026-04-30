# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "ipaddr"
require "tracebook/redaction/scoped_memory"
require "tracebook/redaction/scoped_result_cache"

module Tracebook
  module Redaction
    class OpenAiPrivacyFilter
      DEFAULT_ENDPOINT = "http://127.0.0.1:8765"
      DEFAULT_TIMEOUT = 0.5
      DEFAULT_FAILURE_MODE = :fallback
      FAILURE_MODES = %i[fallback raise].freeze

      class ClientError < StandardError; end

      CLIENT_FAILURES = [
        ClientError,
        JSON::ParserError,
        ArgumentError,
        TypeError,
        IOError,
        SystemCallError,
        SocketError,
        Timeout::Error,
        Net::OpenTimeout,
        Net::ReadTimeout,
        EOFError,
        URI::Error
      ].freeze
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

      Span = Data.define(:start, :end, :label)

      attr_reader :client, :failure_mode, :label_map

      def self.normalize_label_map(label_map)
        label_map.to_h.transform_keys(&:to_s).transform_values(&:to_s)
      end

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
        client: nil,
        scoped_memory: ScopedMemory.new,
        scoped_result_cache: ScopedResultCache.new
      )
        @client = client || Client.new(endpoint: endpoint, timeout: timeout)
        self.class.validate_failure_mode!(failure_mode)
        @failure_mode = failure_mode.to_sym
        @label_map = DEFAULT_LABEL_MAP.merge(self.class.normalize_label_map(label_map))
        @scoped_memory = scoped_memory
        @scoped_result_cache = scoped_result_cache
      end

      def call(text, scope: nil)
        return text unless text.is_a?(String)

        return redact_without_scope(text) if scope.nil?

        cached = scoped_result_cache.read(scope, text)
        return cached unless cached.nil?

        scoped_text = apply_scoped_memory(text, scope)
        spans = selected_spans(scoped_text, spans_from(client.detect(scoped_text)))
        scoped_result_cache.invalidate_scope(scope) if record_spans(scoped_text, spans, scope)
        scoped_result_cache.write(scope, text, replace_spans(scoped_text, spans))
      rescue *CLIENT_FAILURES
        handle_failure(defined?(scoped_text) ? scoped_text : text, $!)
      end

      private

      attr_reader :scoped_memory, :scoped_result_cache

      def redact_without_scope(text)
        replace_spans(text, selected_spans(text, spans_from(client.detect(text))))
      rescue *CLIENT_FAILURES
        handle_failure(text, $!)
      end

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

      def replace_spans(text, spans)
        return text if spans.empty?

        spans.reverse_each.with_object(text.dup) do |span, result|
          result[span.start...span.end] = label_map.fetch(span.label)
        end
      end

      def selected_spans(text, spans)
        merge_adjacent_same_label_spans(select_non_overlapping_spans(text, spans))
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

      def apply_scoped_memory(text, scope)
        matches = select_scoped_memory_matches(text, scoped_memory.entries_for(scope))
        replace_spans(text, matches)
      end

      def record_spans(text, spans, scope)
        changed = false

        spans.each do |span|
          changed = true if scoped_memory.record(scope, text[span.start...span.end], span.label)
        end

        changed
      end

      def select_scoped_memory_matches(text, entries)
        candidates = entries.flat_map do |substring, label|
          scoped_memory_matches(text, substring, label)
        end

        select_longest_non_overlapping_spans(candidates)
      end

      def scoped_memory_matches(text, substring, label)
        matches = []
        start_at = 0

        while (start_offset = text.index(substring, start_at))
          matches << Span.new(start_offset, start_offset + substring.length, label)
          start_at = start_offset + substring.length
        end

        matches
      end

      def select_longest_non_overlapping_spans(spans)
        selected = []

        spans
          .sort_by { |span| [ -(span.end - span.start), span.start, span.label ] }
          .each do |span|
            next if selected.any? { |selected_span| spans_overlap?(selected_span, span) }

            selected << span
          end

        selected.sort_by(&:start)
      end

      def spans_overlap?(first, second)
        first.start < second.end && second.start < first.end
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

# frozen_string_literal: true

require "active_support/core_ext/hash/indifferent_access"
require "active_support/core_ext/object/deep_dup"

module Tracebook
  module Mappers
    class Base
      def normalize(raw_request:, raw_response:, meta: {})
        raise NotImplementedError
      end

      private

      def build_interaction(**attributes)
        NormalizedInteraction.new(**attributes)
      end

      def indifferent_meta(meta)
        (meta || {}).with_indifferent_access
      end

      def symbolize(hash)
        hash.deep_dup.transform_keys { |key| key.respond_to?(:to_sym) ? key.to_sym : key }
      end

      def compact_hash(hash)
        hash.each_with_object({}) do |(key, value), memo|
          next if value.nil?

          memo[key] = value
        end
      end

      # Extract token count from meta (explicit) or response (extracted)
      def token_count(meta, meta_key, response, response_key)
        meta[meta_key]&.to_i || extract_usage_token(response, response_key)
      end

      def extract_usage_token(response, key)
        usage = response[:usage] || {}
        usage.with_indifferent_access[key]&.to_i
      end
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)

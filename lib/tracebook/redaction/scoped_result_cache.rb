# frozen_string_literal: true

module Tracebook
  module Redaction
    class ScopedResultCache
      DEFAULT_MAX_ENTRIES = 2_000

      def initialize(max_entries: DEFAULT_MAX_ENTRIES)
        @max_entries = max_entries
        @entries = {}
        @mutex = Mutex.new
      end

      def read(scope, text)
        key = cache_key(scope, text)

        mutex.synchronize do
          return unless entries.key?(key)

          value = entries.delete(key)
          entries[key] = value
        end
      end

      def write(scope, text, value)
        key = cache_key(scope, text)

        mutex.synchronize do
          entries.delete(key)
          entries[key] = value
          entries.shift while entries.size > max_entries
        end

        value
      end

      def invalidate_scope(scope)
        key_prefix = normalized_scope(scope)

        mutex.synchronize do
          entries.delete_if { |(entry_scope, _text), _value| entry_scope == key_prefix }
        end
      end

      private

      attr_reader :entries, :max_entries, :mutex

      def cache_key(scope, text)
        [ normalized_scope(scope), text ]
      end

      def normalized_scope(scope)
        # Scope may be an Integer, String, UUID-like object, or app-specific value.
        # Pairing class with string value avoids collisions like 1 and "1".
        [ scope.class.name || scope.class.inspect, scope.to_s ]
      end
    end
  end
end

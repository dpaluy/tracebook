# frozen_string_literal: true

module Tracebook
  module Redaction
    class ScopedMemory
      DEFAULT_MAX_SCOPES = 1_000
      DEFAULT_MAX_ENTRIES_PER_SCOPE = 100
      DEFAULT_MIN_LENGTH = 4

      def initialize(
        max_scopes: DEFAULT_MAX_SCOPES,
        max_entries_per_scope: DEFAULT_MAX_ENTRIES_PER_SCOPE,
        min_length: DEFAULT_MIN_LENGTH
      )
        @max_scopes = max_scopes
        @max_entries_per_scope = max_entries_per_scope
        @min_length = min_length
        @scopes = {}
        @mutex = Mutex.new
      end

      def entries_for(scope)
        key = normalized_scope(scope)

        mutex.synchronize do
          bucket = scopes.delete(key)
          return [] unless bucket

          scopes[key] = bucket
          bucket.entries
        end
      end

      def record(scope, substring, label)
        return if scope.nil? || !substring.is_a?(String)
        return if substring.length < min_length

        key = normalized_scope(scope)

        mutex.synchronize do
          bucket = scopes.delete(key) || BoundedHash.new(max_entries: max_entries_per_scope)
          changed = bucket.write(substring, label.to_s)
          scopes[key] = bucket
          evict_oldest_scope
          changed
        end
      end

      private

      attr_reader :max_scopes, :max_entries_per_scope, :min_length, :mutex, :scopes

      def normalized_scope(scope)
        # Scope may be an Integer, String, UUID-like object, or app-specific value.
        # Pairing class with string value avoids collisions like 1 and "1".
        [ scope.class.name || scope.class.inspect, scope.to_s ]
      end

      def evict_oldest_scope
        scopes.shift while scopes.size > max_scopes
      end

      class BoundedHash
        def initialize(max_entries:)
          @max_entries = max_entries
          @entries = {}
          @mutex = Mutex.new
        end

        def entries
          mutex.synchronize { @entries.to_a }
        end

        def write(key, value)
          mutex.synchronize do
            changed = @entries[key] != value
            @entries.delete(key)
            @entries[key] = value
            @entries.shift while @entries.size > max_entries
            changed
          end
        end

        private

        attr_reader :max_entries, :mutex
      end
    end
  end
end

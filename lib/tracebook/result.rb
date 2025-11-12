# frozen_string_literal: true

module Tracebook
  # Result object returned by {TraceBook.record!}.
  #
  # Contains either the persisted interaction (when sync) or success/error information.
  #
  # @example Successful async recording
  #   result = TraceBook.record!(provider: "openai", model: "gpt-4o", ...)
  #   result.success? # => true
  #   result.interaction # => nil (async - not available yet)
  #
  # @example Successful sync recording
  #   TraceBook.configure { |c| c.persist_async = false }
  #   result = TraceBook.record!(provider: "openai", model: "gpt-4o", ...)
  #   result.success? # => true
  #   result.interaction # => #<TraceBook::Interaction id: 123>
  #
  # @example Failed recording
  #   result = TraceBook.record!(provider: nil, model: nil) # Invalid
  #   result.success? # => false
  #   result.error # => #<KeyError: key not found: :provider>
  class Result
    # @return [TraceBook::Interaction, nil] The persisted interaction (sync mode only)
    attr_reader :interaction

    # @return [Exception, nil] The error that occurred during recording
    attr_reader :error

    # @return [String, nil] Idempotency key for deduplication
    attr_reader :idempotency_key

    # Creates a new Result.
    #
    # @param interaction [TraceBook::Interaction, nil] Persisted interaction
    # @param error [Exception, nil] Error that occurred
    # @param idempotency_key [String, nil] Deduplication key
    def initialize(interaction: nil, error: nil, idempotency_key: nil)
      @interaction = interaction
      @error = error
      @idempotency_key = idempotency_key
    end

    # Returns true if recording succeeded (no error).
    #
    # @return [Boolean] true when no error occurred
    def success?
      error.nil?
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)

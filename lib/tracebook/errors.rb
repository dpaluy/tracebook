# frozen_string_literal: true

module Tracebook
  class Error < StandardError; end

  class ConfigurationError < Error; end
end

TraceBook = Tracebook unless defined?(TraceBook)

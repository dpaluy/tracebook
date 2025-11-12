# frozen_string_literal: true

require_relative "adapters/ruby_llm"
require_relative "adapters/active_agent"

TraceBook = Tracebook unless defined?(TraceBook)

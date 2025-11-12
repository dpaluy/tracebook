# frozen_string_literal: true

require_relative "redactors/base"
require_relative "redactors/email"
require_relative "redactors/phone"
require_relative "redactors/card_pan"

TraceBook = Tracebook unless defined?(TraceBook)

# frozen_string_literal: true

namespace :tracebook do
  desc "Seed default pricing rules for common LLM providers (Gemini, OpenAI, Anthropic, Ollama)"
  task seed_pricing: :environment do
    result = Tracebook::Seeds::PricingRules.seed!

    puts "TraceBook pricing rules seeded!"
    puts "  Created: #{result[:created]}"
    puts "  Skipped (already exist): #{result[:skipped]}"

    puts "\nRun again after gem updates to add new model pricing." if result[:created] > 0
  end
end

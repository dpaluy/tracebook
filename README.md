# TraceBook

[![Gem Version](https://img.shields.io/gem/v/tracebook.svg)](https://rubygems.org/gems/tracebook)
[![CI](https://github.com/dpaluy/tracebook/actions/workflows/ci.yml/badge.svg)](https://github.com/dpaluy/tracebook/actions/workflows/ci.yml)

> **Note:** This gem is in active development. APIs may change before 1.0 release.

TraceBook is a Rails engine that ingests, redacts, and reviews LLM interactions with optional encryption. It ships with a Hotwire UI, cost tracking, rollup analytics, and adapters for popular Ruby LLM libraries.

## Features

- **Privacy-first**: Request/response payloads are redacted (PII removal) with optional encryption at rest
- **Cost tracking**: Automatic token usage and cost calculation per provider/model
- **Review workflow**: Approve, flag, or reject interactions with audit trail
- **Hierarchical sessions**: Track parent-child relationships for agent chains
- **Analytics**: Daily rollups for reporting and cost analysis
- **Flexible adapters**: Built-in support for multiple providers; easy to extend
- **Production-ready**: Async job processing, export to CSV/NDJSON, filterable dashboards

## Requirements

- Ruby 3.2+
- Rails 8.1+
- ActiveJob backend (`:async` for development; Sidekiq/SolidQueue for production)
- Database with JSONB support (PostgreSQL recommended)

## Table of Contents

- [Installation](#installation--setup)
- [Configuration](#configuration)
- [Capturing Interactions](#capturing-interactions)
  - [Manual API](#manual-api)
  - [Built-in Adapters](#built-in-adapters)
- [Creating Custom Adapters](#creating-custom-adapters)
- [Creating Custom Mappers](#creating-custom-mappers)
- [Cost Tracking](#cost-tracking)
- [Reviewing Data](#reviewing-data)
- [Production Setup](#production-setup)
  - [Securing the Dashboard](#securing-the-dashboard)
- [Development & Testing](#development--testing)

## Installation & Setup

```bash
bundle add tracebook
bin/rails generate tracebook:install
bin/rails db:migrate
```

The install generator copies migrations and creates `config/initializers/tracebook.rb`.

### Mount the engine

Add to `config/routes.rb`:

```ruby
mount TraceBook::Engine => "/tracebook"
```

See [Securing the Dashboard](#securing-the-dashboard) for authentication options.

### Optional: Configure encryption

TraceBook supports ActiveRecord::Encryption for encrypting sensitive payload data at rest. This is **optional** but recommended for production environments handling sensitive data.

**Step 1: Generate encryption keys**

```bash
bin/rails db:encryption:init
```

This outputs:

```yaml
active_record_encryption:
  primary_key: [generated_key]
  deterministic_key: [generated_key]
  key_derivation_salt: [generated_salt]
```

**Step 2: Add keys to credentials**

```bash
EDITOR=vim bin/rails credentials:edit
```

```yaml
# config/credentials.yml.enc
active_record_encryption:
  primary_key: <generated_key>
  deterministic_key: <generated_key>
  key_derivation_salt: <generated_salt>
```

**Step 3: Enable encryption in your app**

Create an initializer to add encryption to the Interaction model:

```ruby
# config/initializers/tracebook_encryption.rb
Rails.application.config.after_initialize do
  Tracebook::Interaction.class_eval do
    encrypts :request_payload, :response_payload
  end
end
```

> **Note**: Enabling encryption on an existing database requires migrating existing unencrypted data. See the [Rails encryption guide](https://guides.rubyonrails.org/active_record_encryption.html) for migration strategies.

## Configuration

The install generator creates `config/initializers/tracebook.rb` with sensible defaults.

Available options:

```ruby
TraceBook.configure do |config|
  # Project identifier for filtering in the dashboard
  config.project_name = "My App"

  # Use async jobs for persistence (default: true)
  # Set to false for tests or simple setups
  config.persist_async = Rails.env.production?

  # Payload size threshold for ActiveStorage spillover (default: 64KB)
  config.inline_payload_bytes = 64 * 1024

  # Auto-enable adapters on boot
  config.auto_subscribe_ruby_llm = true
  config.auto_subscribe_active_agent = true

  # Custom PII redactors (in addition to built-in email/phone/card)
  config.custom_redactors += [
    ->(payload) { payload.gsub(/api_key=\w+/, "api_key=[REDACTED]") }
  ]
end
```

Configuration is frozen after the block runs. Call `TraceBook.reset_configuration!` in tests when you need a clean slate.

## Capturing Interactions

### Manual API

Call `TraceBook.record!` anywhere you have access to an LLM request/response:

```ruby
TraceBook.record!(
  provider: "openai",
  model: "gpt-4o-mini",
  project: "support",
  request_payload: { messages: messages, temperature: 0.2 },
  response_payload: response_body,
  input_tokens: usage[:prompt_tokens],
  output_tokens: usage[:completion_tokens],
  latency_ms: 187,
  status: :success,
  tags: %w[triage priority],
  metadata: { ticket_id: ticket.id },
  user: current_user,
  session_id: session_id,
  parent_id: parent_interaction_id
)
```

**Parameters:**

- **Required:**
  - `provider` (String) — LLM provider name (e.g., "openai", "anthropic", "ollama")
  - `model` (String) — Model identifier (e.g., "gpt-4o", "claude-3-5-sonnet-20241022")

- **Optional:**
  - `project` (String) — Project/app name for filtering
  - `request_payload` (Hash) — Full request sent to provider
  - `response_payload` (Hash) — Full response from provider
  - `request_text` (String) — Human-readable request summary
  - `response_text` (String) — Human-readable response summary
  - `input_tokens` (Integer) — Prompt token count
  - `output_tokens` (Integer) — Completion token count
  - `latency_ms` (Integer) — Request duration in milliseconds
  - `status` (Symbol) — `:success`, `:error`, `:canceled`
  - `error_class` (String) — Exception class name on failure
  - `error_message` (String) — Exception message on failure
  - `tags` (Array<String>) — Labels for filtering (e.g., ["prod", "high-priority"])
  - `metadata` (Hash) — Custom metadata (e.g., `{ ticket_id: 123 }`)
  - `user` (ActiveRecord object) — Associated user (polymorphic)
  - `session_id` (String) — Session identifier for grouping related calls
  - `parent_id` (Integer) — Parent `Interaction` ID for hierarchical chains

**Return value:**

```ruby
result = TraceBook.record!(...)
result.success?    # => true/false
result.error       # => exception when persistence failed
result.interaction # => AR record when persisted inline (persist_async = false)
```

When `config.persist_async = true`, the interaction is enqueued via `Tracebook::PersistInteractionJob`.

### Background Jobs & Rollups

**PersistInteractionJob** handles redaction, cost calculation, and writes the `Interaction` record.

**DailyRollupsJob** summarizes counts, token totals, and cost into `RollupDaily` rows. Schedule it nightly per provider/model/project:

```ruby
# Example: Schedule with Sidekiq Cron or whenever
Tracebook::DailyRollupsJob.perform_later(
  date: Date.yesterday,
  provider: "openai",
  model: "gpt-4o",
  project: nil
)
```

Wrap this in your scheduler to cover all active provider/model/project combinations.

**ExportJob** streams large CSV/NDJSON exports respecting your filters.

## Built-in Adapters

TraceBook ships with adapters that automatically capture LLM interactions from popular libraries. Adapters normalize provider-specific responses and call `TraceBook.record!`, so you get instrumentation without modifying application code.

### RubyLLM Adapter

The RubyLLM adapter subscribes to `ActiveSupport::Notifications` events (default: `ruby_llm.request`).

**Setup:**

```ruby
# config/initializers/tracebook_adapters.rb
TraceBook::Adapters::RubyLLM.enable!
```

**Emit events from your LLM client:**

```ruby
# Example: Wrapping an OpenAI client call
class OpenAIService
  def chat_completion(messages:, model: "gpt-4o", **options)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    request = {
      model: model,
      messages: messages,
      **options
    }

    begin
      response = openai_client.chat(parameters: request)
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).to_i

      ActiveSupport::Notifications.instrument("ruby_llm.request", {
        provider: "openai",
        request: request,
        response: response,
        meta: {
          project: "support-chatbot",
          tags: ["customer-support", "triage"],
          user: current_user,
          session_id: session.id,
          latency_ms: elapsed_ms,
          status: :success,
          # Token counts can be passed explicitly or extracted from response
          input_tokens: response.dig("usage", "prompt_tokens"),
          output_tokens: response.dig("usage", "completion_tokens")
        }
      })

      response
    rescue => e
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).to_i

      ActiveSupport::Notifications.instrument("ruby_llm.request", {
        provider: "openai",
        request: request,
        response: nil,
        meta: {
          project: "support-chatbot",
          user: current_user,
          session_id: session.id,
          latency_ms: elapsed_ms,
          status: :error,
          error_class: e.class.name,
          error_message: e.message
        }
      })

      raise
    end
  end

  private

  def openai_client
    @openai_client ||= OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
  end
end
```

**Supported providers:** OpenAI, Anthropic, Ollama (built-in mappers). Other providers use the fallback mapper.

**Token extraction:**

Mappers extract token counts from two sources (in priority order):
1. **Explicit `meta` values**: Pass `input_tokens` and `output_tokens` in the `meta` hash
2. **Response payload**: If not in meta, mappers extract from provider-specific response fields (e.g., `usage.prompt_tokens` for OpenAI, `usage.input_tokens` for Anthropic)

If your LLM client strips the `usage` object from responses, pass tokens explicitly via `meta`.

**Custom event name:**

```ruby
# If your library uses a different event name
TraceBook::Adapters::RubyLLM.enable!(instrumentation: "my_llm.complete")
```

**Disabling:**

```ruby
# In test environment or when switching instrumentation
TraceBook::Adapters::RubyLLM.disable!
```

### ActiveAgent Adapter

For applications using ActiveAgent (agentic frameworks), enable the bus adapter:

```ruby
# config/initializers/tracebook_adapters.rb
TraceBook::Adapters::ActiveAgent.enable!(bus: ActiveAgent::Bus)
```

The adapter automatically captures agent interactions including parent-child relationships for hierarchical agent chains.

**Note:** If you omit `bus:`, the adapter attempts to locate `ActiveAgent::Bus` automatically when loaded.

## Creating Custom Adapters

Adapters follow a simple pattern:

1. Listen to whatever instrumentation your LLM client exposes (Notifications, middleware, observers, etc.)
2. Normalize the payload using `Tracebook::Mappers.normalize` or build a `NormalizedInteraction` manually
3. Call `TraceBook.record!(**normalized.to_h)`

**Example: Custom adapter for Langchain.rb**

```ruby
# lib/tracebook/adapters/langchain_rb.rb
module Tracebook
  module Adapters
    module LangchainRb
      extend self

      def enable!
        return if @enabled

        # Hook into Langchain's middleware or callback system
        ::Langchain::LLM::Base.after_completion do |llm, request, response, duration|
          handle_completion(
            provider: llm.class.provider_name,
            request: request,
            response: response,
            duration_ms: (duration * 1000).to_i,
            meta: {
              project: "langchain-app",
              user: Current.user,
              session_id: Current.session_id
            }
          )
        end

        @enabled = true
      end

      def disable!
        # Unhook callback
        @enabled = false
      end

      private

      def handle_completion(provider:, request:, response:, duration_ms:, meta:)
        normalized = Tracebook::Mappers.normalize(
          provider,
          raw_request: request,
          raw_response: response,
          meta: meta.merge(latency_ms: duration_ms)
        )

        TraceBook.record!(**normalized.to_h)
      rescue => error
        Rails.logger.error("TraceBook LangchainRb adapter error: #{error.message}")
      end
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
```

**Enable your adapter:**

```ruby
# config/initializers/tracebook_adapters.rb
require "tracebook/adapters/langchain_rb"
Tracebook::Adapters::LangchainRb.enable!
```

## Creating Custom Mappers

Mappers normalize provider-specific request/response formats into TraceBook's standard schema. Create a custom mapper when the built-in ones (OpenAI, Anthropic, Ollama) don't match your provider's format.

**Example: Custom mapper for Cohere**

```ruby
# lib/tracebook/mappers/cohere.rb
module Tracebook
  module Mappers
    class Cohere < Base
      def self.normalize(raw_request:, raw_response:, meta: {})
        new.normalize(
          raw_request: raw_request,
          raw_response: raw_response,
          meta: meta
        )
      end

      def normalize(raw_request:, raw_response:, meta: {})
        request = symbolize(raw_request || {})
        response = symbolize(raw_response || {})
        meta_info = indifferent_meta(meta)

        build_interaction(
          provider: "cohere",
          model: request[:model] || response[:model],
          project: meta_info[:project],
          request_payload: raw_request,
          response_payload: raw_response,
          request_text: request[:message] || request[:prompt],
          response_text: extract_response_text(response),
          input_tokens: extract_token_count(response, :prompt_tokens),
          output_tokens: extract_token_count(response, :completion_tokens),
          latency_ms: meta_info[:latency_ms],
          status: meta_info[:status]&.to_sym || :success,
          error_class: nil,
          error_message: nil,
          tags: Array(meta_info[:tags]).compact,
          metadata: extract_metadata(response),
          user: meta_info[:user],
          parent_id: meta_info[:parent_id],
          session_id: meta_info[:session_id]
        )
      end

      private

      def extract_response_text(response)
        response[:text] || response.dig(:generations, 0, :text)
      end

      def extract_token_count(response, key)
        response.dig(:meta, :billed_units, key)&.to_i
      end

      def extract_metadata(response)
        metadata = {}
        metadata["generation_id"] = response[:generation_id] if response[:generation_id]
        metadata["finish_reason"] = response[:finish_reason] if response[:finish_reason]
        compact_hash(metadata)
      end
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
```

**Register your mapper:**

```ruby
# lib/tracebook/mappers.rb
require_relative "mappers/cohere"

module Tracebook
  module Mappers
    def normalize(provider, raw_request:, raw_response:, meta: {})
      case provider.to_s
      when "openai"
        normalize_openai(raw_request, raw_response, meta)
      when "anthropic"
        normalize_anthropic(raw_request, raw_response, meta)
      when "ollama"
        normalize_ollama(raw_request, raw_response, meta)
      when "cohere"
        Mappers::Cohere.normalize(
          raw_request: raw_request,
          raw_response: raw_response,
          meta: meta
        )
      else
        fallback_normalized(provider, raw_request, raw_response, meta)
      end
    end
  end
end
```

**Mapper requirements:**

- Inherit from `Tracebook::Mappers::Base`
- Implement `.normalize(raw_request:, raw_response:, meta:)`
- Return a `Tracebook::NormalizedInteraction` instance
- Handle missing fields gracefully (return `nil` for unavailable data)
- Extract token counts if available, otherwise leave as `nil`

## Cost Tracking

TraceBook automatically calculates costs based on `PricingRule` records. Create pricing rules for your providers/models:

```ruby
# db/seeds.rb or a migration

# OpenAI pricing (as of 2024)
# Costs are in cents per 1000 tokens
TraceBook::PricingRule.create!(
  provider: "openai",
  model_glob: "gpt-4o",
  input_cents_per_unit: 250,   # $2.50 per 1k tokens = 250 cents
  output_cents_per_unit: 1000, # $10.00 per 1k tokens = 1000 cents
  currency: "USD",
  effective_from: Date.new(2024, 8, 6)
)

TraceBook::PricingRule.create!(
  provider: "openai",
  model_glob: "gpt-4o-mini*",
  input_cents_per_unit: 15,    # $0.15 per 1k tokens
  output_cents_per_unit: 60,   # $0.60 per 1k tokens
  currency: "USD",
  effective_from: Date.new(2024, 7, 18)
)

TraceBook::PricingRule.create!(
  provider: "openai",
  model_glob: "o1*",
  input_cents_per_unit: 1500,  # $15.00 per 1k tokens
  output_cents_per_unit: 6000, # $60.00 per 1k tokens
  currency: "USD",
  effective_from: Date.new(2024, 12, 17)
)

# Anthropic pricing
TraceBook::PricingRule.create!(
  provider: "anthropic",
  model_glob: "claude-3-5-sonnet-*",
  input_cents_per_unit: 300,   # $3.00 per 1k tokens
  output_cents_per_unit: 1500, # $15.00 per 1k tokens
  currency: "USD",
  effective_from: Date.new(2024, 10, 22)
)

TraceBook::PricingRule.create!(
  provider: "anthropic",
  model_glob: "claude-3-5-haiku-*",
  input_cents_per_unit: 100,   # $1.00 per 1k tokens
  output_cents_per_unit: 500,  # $5.00 per 1k tokens
  currency: "USD",
  effective_from: Date.new(2024, 11, 1)
)

# Ollama (free/local)
TraceBook::PricingRule.create!(
  provider: "ollama",
  model_glob: "*",
  input_cents_per_unit: 0,
  output_cents_per_unit: 0,
  currency: "USD",
  effective_from: Date.new(2024, 1, 1)
)
```

**Glob patterns:**

- `gpt-4o` — Exact match
- `gpt-4o*` — Matches `gpt-4o`, `gpt-4o-mini`, `gpt-4o-2024-08-06`
- `claude-3-5-*` — Matches all Claude 3.5 models
- `*` — Matches everything (fallback rule)

TraceBook uses the most specific matching rule. If multiple rules match, it prefers the most recently effective one.

## Reviewing Data

### Dashboard UI

Visit the mount path (`/tracebook` by default) to access the dashboard.

**Index screen:**

- **Filters**: Provider, model, project, status, review state, tags, date range
- **KPI tiles**: Total calls, tokens used, total cost, error rate, avg latency
- **Interaction table**: Columns include:
  - Timestamp
  - Label (first 100 chars of request)
  - User
  - Provider/Model
  - Tokens (input/output)
  - Cost
  - Duration (ms)
  - Review state
  - Actions (Approve/Flag/Reject, detail link)

**Detail screen:**

- **Header**: ID, label, user, timestamp, review state dropdown + comment form
- **Metrics panel**: Model, duration, token breakdown, cost, HTTP status
- **Collapsible sections**:
  - Input (messages)
  - Output (text + tool calls)
  - Full JSON (request/response payloads)
  - Error (if failed)
- **Sidebar**: Parent/child links, tags, session breadcrumb

**Keyboard shortcuts:**

- `j/k` — Navigate rows
- `a` — Approve selected
- `f` — Flag selected
- `r` — Reject selected
- `?` — Show help

**Bulk review:**

Select multiple interactions using checkboxes, then apply a review state to all at once.

### Review Workflow

Interactions start in `unreviewed` state. Reviewers can transition to:

- **`approved`** — Interaction is acceptable; no issues found
- **`flagged`** — Interaction requires attention (e.g., sensitive data, unexpected behavior)
- **`rejected`** — Interaction is problematic and should not have occurred

Only `admin` users (as defined in your `authorize` proc) can change review states.

## Production Setup

### Securing the Dashboard

The dashboard should only be accessible to trusted reviewers. Here are common approaches:

**Devise with admin check:**

```ruby
# config/routes.rb
authenticate :user, ->(u) { u.admin? } do
  mount TraceBook::Engine => "/tracebook"
end
```

**Session-based constraint:**

```ruby
# config/routes.rb
constraints ->(req) { req.session[:admin] } do
  mount TraceBook::Engine => "/tracebook"
end
```

**HTTP Basic Auth (simple setups):**

```ruby
# config/routes.rb
TraceBook::Engine.middleware.use Rack::Auth::Basic do |username, password|
  ActiveSupport::SecurityUtils.secure_compare(username, ENV["TRACEBOOK_USER"]) &
    ActiveSupport::SecurityUtils.secure_compare(password, ENV["TRACEBOOK_PASSWORD"])
end

mount TraceBook::Engine => "/tracebook"
```

### Queue Adapter

Configure ActiveJob to use a production queue backend:

```ruby
# config/environments/production.rb
config.active_job.queue_adapter = :sidekiq # or :solid_queue, etc.
```

### Encryption Keys (if enabled)

If you've enabled payload encryption (see [Configure encryption](#optional-configure-encryption)), store keys securely:

- Use Rails encrypted credentials (`bin/rails credentials:edit`)
- Or environment variables with a secrets manager (AWS Secrets Manager, HashiCorp Vault)

### Scheduling Rollup Jobs

Use a scheduler to run `DailyRollupsJob` nightly:

**Sidekiq Cron:**

```ruby
# config/initializers/sidekiq_cron.rb
Sidekiq::Cron::Job.create(
  name: "TraceBook daily rollups - OpenAI",
  cron: "0 2 * * *", # 2am daily
  class: "Tracebook::DailyRollupsJob",
  kwargs: { date: Date.yesterday, provider: "openai", model: nil, project: nil }
)
```

**Whenever:**

```ruby
# config/schedule.rb
every 1.day, at: "2:00 am" do
  runner "Tracebook::DailyRollupsJob.perform_later(date: Date.yesterday, provider: 'openai', model: nil, project: nil)"
end
```

### Monitoring

Add error tracking to catch adapter failures:

```ruby
# config/initializers/tracebook.rb
TraceBook.configure do |config|
  # Existing config...

  # Hook into error logging
  config.on_error = ->(error, context) do
    Sentry.capture_exception(error, extra: context) if defined?(Sentry)
    Rails.logger.error("TraceBook error: #{error.message} - #{context.inspect}")
  end
end
```

### Database Indexes

TraceBook migrations include indexes for common queries. If you add custom filters, consider additional indexes:

```ruby
# db/migrate/xxx_add_custom_tracebook_indexes.rb
class AddCustomTracebookIndexes < ActiveRecord::Migration[7.1]
  def change
    add_index :tracebook_interactions, [:project, :occurred_at], name: "idx_tracebook_project_time"
    add_index :tracebook_interactions, :tags, using: :gin, name: "idx_tracebook_tags"
  end
end
```

### Data Retention

Consider archiving or deleting old interactions to manage database size:

```ruby
# app/jobs/archive_old_interactions_job.rb
class ArchiveOldInteractionsJob < ApplicationJob
  def perform
    cutoff = 90.days.ago

    # Option 1: Delete
    TraceBook::Interaction.where("occurred_at < ?", cutoff).delete_all

    # Option 2: Export to S3 before deleting
    interactions = TraceBook::Interaction.where("occurred_at < ?", cutoff)
    S3Archiver.archive(interactions)
    interactions.delete_all
  end
end
```

## Development & Testing

### Inside the engine repository

```bash
cd tracebook/
bundle install
bundle exec rails db:migrate   # Run dummy app migrations
bundle exec rake test          # Run full test suite
bundle exec rubocop --fix-unsafe # Fix style issues
```

### Inside a host application

After updating the gem, install any new migrations:

```bash
bin/rails tracebook:install:migrations
bin/rails db:migrate
```

### Testing with adapters disabled

```ruby
# test/test_helper.rb
class ActiveSupport::TestCase
  setup do
    TraceBook::Adapters::RubyLLM.disable!
    TraceBook.reset_configuration!

    TraceBook.configure do |config|
      config.authorize = ->(*) { true }
      config.persist_async = false # Inline for tests
    end
  end
end
```

## API Documentation

TraceBook uses [YARD](https://yardoc.org/) for API documentation. The full API docs are available at [rubydoc.info/gems/tracebook](https://rubydoc.info/gems/tracebook).

### Generating Documentation Locally

```bash
# Install YARD
bundle install

# Generate documentation
bundle exec rake yard

# Generate and open in browser
bundle exec rake yard:open

# View documentation coverage stats
bundle exec rake yard:stats
```

Documentation is generated in the `doc/` directory. Open `doc/index.html` in your browser to view.

### Key Documentation Areas

- **{Tracebook}** - Main module and `record!` method
- **{Tracebook::Mappers}** - Provider normalization
- **{Tracebook::Adapters::RubyLLM}** - ActiveSupport::Notifications adapter
- **{Tracebook::Interaction}** - ActiveRecord model
- **{Tracebook::NormalizedInteraction}** - Standard data structure
- **{Tracebook::Result}** - Return value from `record!`

## Contributing

1. Fork the repo and create a topic branch
2. Ensure `bundle exec rake test` passes
3. Update documentation and add regression tests for new behavior
4. Run `bundle exec rubocop -A` to fix style issues
5. Add YARD documentation for new public methods
6. Open a PR describing the motivation and changes

## License

TraceBook is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

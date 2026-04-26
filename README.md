# Tracebook

[![Gem Version](https://img.shields.io/gem/v/tracebook.svg)](https://rubygems.org/gems/tracebook)
[![CI](https://github.com/dpaluy/tracebook/actions/workflows/ci.yml/badge.svg)](https://github.com/dpaluy/tracebook/actions/workflows/ci.yml)

Cost tracking and review dashboard for [RubyLLM](https://github.com/crmne/ruby_llm) conversations.

Tracebook is a Rails engine that sits on top of RubyLLM's `acts_as_chat` and `acts_as_message` models. It adds per-message cost calculation, chat-level review workflows, and a Hotwire-powered dashboard — without duplicating any conversation data.

## Features

- **Cost tracking**: Per-message cost calculation based on configurable pricing rules
- **Review workflow**: Approve or flag entire chat conversations with comments
- **Dashboard**: Browse chats, view conversation threads, see cost/token summaries
- **RubyLLM native**: Reads directly from your Chat and Message models — no data duplication

## Requirements

- Ruby 3.4+
- Rails 8.1+
- [RubyLLM](https://github.com/crmne/ruby_llm) with `acts_as_chat` / `acts_as_message` models

## Installation

```bash
bundle add tracebook
bin/rails generate tracebook:install
bin/rails db:migrate
```

Mount the engine in `config/routes.rb`:

```ruby
mount Tracebook::Engine => "/tracebook"
```

Seed pricing rules for common providers:

```bash
bin/rails tracebook:seed_pricing
```

## Configuration

```ruby
# config/initializers/tracebook.rb
Tracebook.configure do |config|
  # Class names for your RubyLLM models
  config.chat_class = "Chat"       # default
  config.message_class = "Message" # default

  # Currency for cost calculations
  config.default_currency = "USD"  # default

  # How to display the user in the dashboard
  config.actor_display = ->(actor) { actor.try(:name) }

  # Items per page
  config.per_page = 25             # default
end
```

## PII Redaction

Tracebook includes an opt-in PII redaction pipeline for unstructured natural language in LLM conversations. Nothing is redacted unless explicitly configured.

### Enabling Patterns

```ruby
Tracebook.configure do |config|
  # Enable individual patterns
  config.redact :email, :phone, :ssn, :credit_card

  # Or enable a whole group
  config.redact :pii, :api_keys
end
```

### Available Patterns

| Pattern | Detects | Validation |
|---------|---------|------------|
| `email` | Email addresses | -- |
| `phone` | Phone numbers (US format) | -- |
| `ssn` | Social Security Numbers | SSA area-number range check |
| `credit_card` | Credit card numbers | Luhn algorithm |
| `openai_key` | OpenAI API keys (`sk-...`) | -- |
| `anthropic_key` | Anthropic API keys (`sk-ant-...`) | -- |
| `aws_key` | AWS access key IDs (`AKIA...`) | -- |
| `stripe_key` | Stripe API keys | -- |
| `github_token` | GitHub tokens (`ghp_`, `gho_`, etc.) | -- |
| `ipv4` | IPv4 addresses | Octet range 0-255 |
| `bearer_token` | Authorization bearer tokens | -- |
| `jwt` | JSON Web Tokens | -- |
| `private_key` | PEM-format private key blocks | -- |

### Pattern Groups

| Group | Patterns included |
|-------|-------------------|
| `pii` | `email`, `phone`, `ssn` |
| `financial` | `credit_card` |
| `api_keys` | `openai_key`, `anthropic_key`, `aws_key`, `stripe_key`, `github_token` |
| `auth` | `bearer_token`, `jwt` |
| `network` | `ipv4` |
| `crypto` | `private_key` |

### Custom Patterns

```ruby
Tracebook.configure do |config|
  config.redact_pattern(
    /policy[:\s]*\d{10}/i,
    "[POLICY_NUMBER]",
    name: "policy_number"
  )
end
```

### Custom Redactors

Provide any callable (proc, lambda, or object responding to `call`):

```ruby
Tracebook.configure do |config|
  config.custom_redactors << ->(text) {
    text.gsub(/MRN-\d{8}/, "[MEDICAL_RECORD]")
  }
end
```

### OpenAI Privacy Filter

Tracebook can optionally call a local [OpenAI Privacy Filter](https://github.com/openai/privacy-filter) sidecar after regex and custom redactors. It is off by default.

```ruby
Tracebook.configure do |config|
  config.redact :pii, :api_keys, :auth

  config.openai_privacy_filter.enabled = true
  config.openai_privacy_filter.endpoint = "http://127.0.0.1:8765"
  config.openai_privacy_filter.timeout = 0.5
  config.openai_privacy_filter.failure_mode = :fallback
end
```

The endpoint must be `localhost` or a loopback IP address. Tracebook rejects non-loopback endpoints so raw text is not accidentally sent to a hosted service.

The local sidecar should accept `POST /redact` with:

```json
{ "text": "Alice was born on 1990-01-02." }
```

and return OpenAI Privacy Filter JSON with `detected_spans`:

```json
{
  "detected_spans": [
    { "label": "private_person", "start": 0, "end": 5 },
    { "label": "private_date", "start": 18, "end": 28 }
  ]
}
```

Tracebook applies its own stable placeholders instead of trusting model-formatted output:

| Privacy Filter label | Placeholder |
|----------------------|-------------|
| `account_number` | `[ACCOUNT_NUMBER]` |
| `private_address` | `[ADDRESS]` |
| `private_email` | `[EMAIL]` |
| `private_person` | `[PERSON]` |
| `private_phone` | `[PHONE]` |
| `private_url` | `[URL]` |
| `private_date` | `[DATE]` |
| `secret` | `[SECRET]` |

If the local sidecar is down, times out, or returns an invalid response, Tracebook returns the text after regex/custom redaction. It does not raise by default. To raise instead, set `config.openai_privacy_filter.failure_mode = :raise`.

### Using Redaction

```ruby
# Redact text directly
Tracebook.redact("Email user@test.com or call 555-123-4567")
# => "Email [EMAIL] or call [PHONE]"

# Use in your application before saving messages
content = Tracebook.redact(user_input)
chat.ask(content)
```

Enabling OpenAI Privacy Filter only changes what `Tracebook.redact(...)` does. Tracebook does not automatically redact saved messages, dashboard views, or JSON exports.

## Tracebook Tables

Tracebook adds four tables — all prefixed with `tracebook_` to avoid collisions:

| Table | Purpose |
|-------|---------|
| `tracebook_message_costs` | Cost + latency per message (polymorphic join to your Message) |
| `tracebook_chat_reviews` | Review state per chat (polymorphic join to your Chat) |
| `tracebook_comments` | Comments on chat reviews |
| `tracebook_pricing_rules` | Cost per token by provider/model |

Your Chat and Message tables are untouched.

## Cost Calculation

After an LLM response, call `Tracebook.calculate_cost!` to record the cost:

```ruby
Tracebook.calculate_cost!(
  message,
  provider: "openai",
  model: "gpt-4o",
  latency_ms: elapsed_ms
)
```

This looks up the matching pricing rule, calculates input/output costs, and creates a `tracebook_message_costs` record joined to the message.

### Integration Example

In a typical RubyLLM app, hook into the chat response flow:

```ruby
class ChatResponseJob < ApplicationJob
  def perform(chat_id, content)
    chat = Chat.find(chat_id)

    chat.ask(content) do |chunk|
      # stream chunks...
    end

    # After response, calculate cost for the last assistant message
    message = chat.messages.where(role: "assistant").last
    model = chat.model

    Tracebook.calculate_cost!(
      message,
      provider: model.provider,
      model: model.model_id
    )
  end
end
```

## Pricing Rules

Tracebook calculates costs using `PricingRule` records. Seed defaults for common providers:

```bash
bin/rails tracebook:seed_pricing
```

This creates rules for OpenAI, Anthropic, Gemini, and Ollama models.

### Adding Custom Rules

```ruby
Tracebook::PricingRule.create!(
  provider: "xai",
  model_glob: "grok-4-1-fast*",
  input_cents_per_unit: 20,   # per 1k tokens
  output_cents_per_unit: 50,
  effective_from: Date.new(2025, 7, 1),
  currency: "USD"
)
```

### Glob Patterns

- `gpt-4o` — exact match
- `gpt-4o*` — matches `gpt-4o`, `gpt-4o-mini`, `gpt-4o-2024-08-06`
- `claude-3-5-*` — matches all Claude 3.5 models
- `*` — fallback for any model

When multiple rules match, Tracebook prefers the most specific glob (most literal characters), then the most recent `effective_from` date.

## Review Workflow

Reviews happen at the chat level, not per-message. In the dashboard:

1. Open a chat to see the full conversation thread
2. Click **Approve** or **Flag**
3. Add comments for context

Programmatic access:

```ruby
chat = Chat.find(id)
review = Tracebook::ChatReview.for_chat(chat)

review.update!(
  review_state: :approved,
  reviewed_by: "admin@example.com"
)

review.comments.create!(author: "admin", body: "Looks good")
```

### Review States

| State | Meaning |
|-------|---------|
| `pending` | Not yet reviewed (default) |
| `approved` | Reviewed and accepted |
| `flagged` | Needs attention |

## Dashboard

The dashboard is available at `/tracebook/chats` (or wherever you mount the engine).

### Chat List (`/tracebook/chats`)
- All chats with actor, model, message count, token usage, cost, review state
- KPIs: total chats, messages, cost

### Chat Detail (`/tracebook/chats/:id`)
- Full conversation thread (user and assistant messages)
- Per-message token counts and costs
- Review controls (approve/flag/reset)
- Comment thread

### Actor Display

By default, actors are shown as `Name` or `ClassName#id`. Customize with:

```ruby
config.actor_display = ->(actor) {
  case actor
  when User then actor.email
  else "#{actor.class}##{actor.id}"
  end
}
```

## Securing the Dashboard

The engine inherits from `ActionController::Base`. Restrict access with route constraints:

```ruby
# HTTP Basic Auth
mount Tracebook::Engine => "/tracebook",
  constraints: ->(req) {
    Rack::Auth::Basic::Request.new(req.env).provided? &&
    Rack::Auth::Basic::Request.new(req.env).credentials == ["admin", ENV["TRACEBOOK_PASSWORD"]]
  }

# Devise
authenticate :user, ->(u) { u.admin? } do
  mount Tracebook::Engine => "/tracebook"
end
```

## Development & Testing

```bash
# Run tests
bin/rails test

# Seed pricing in development
bin/rails tracebook:seed_pricing
```

### Reset configuration in tests

```ruby
setup { Tracebook.reset_configuration! }
teardown { Tracebook.reset_configuration! }
```

## License

MIT License. See [MIT-LICENSE](MIT-LICENSE).

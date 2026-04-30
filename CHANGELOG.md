# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- **Chat-scoped redaction memory**: `Tracebook.redact(text, scope:)` can now propagate exact model-detected private substrings within a conversation/session and cache scoped redaction results in-process.

### Changed

- **Dashboard redaction**: Chat HTML rendering and chat JSON export now call `Tracebook.redact(message.content, scope: chat.id)` so configured redaction applies consistently in the dashboard.

## [1.1.0] - 2026-04-26

### Added

- **OpenAI Privacy Filter redaction backend**: Added an optional local sidecar-backed redactor for context-sensitive PII detection. Apps can enable it with `config.openai_privacy_filter.enabled = true` and configure the loopback endpoint, timeout, failure mode, and label placeholders.
- **Stable model placeholders**: Privacy Filter spans are mapped to Tracebook-owned placeholders such as `[PERSON]`, `[ADDRESS]`, `[DATE]`, `[SECRET]`, and `[ACCOUNT_NUMBER]`.

### Changed

- **Explicit redaction placement preserved**: Enabling OpenAI Privacy Filter only changes `Tracebook.redact(...)`; Tracebook does not automatically redact saved messages, dashboard views, JSON exports, or RubyLLM callbacks.
- **Sidecar failures fall back safely**: If the local sidecar is down, times out, returns a non-success response, invalid JSON, or an unexpected response shape, Tracebook falls back to the regex/custom-redacted text instead of raising by default.
- **Dashboard script loading hardened**: Removed the fallback CDN load of Stimulus so Tracebook dashboard pages do not execute third-party JavaScript in pages that can display conversation content.
- **Dependency patches**: Updated the locked Rails/Rack/Nokogiri/Loofah/Trix/JSON dependency set to patched versions reported clean by `bundle audit`.

## [1.0.1] - 2026-03-26

### Fixed

- **Engine migrations**: Restored guard to skip appending engine migration paths when running inside the dummy app, fixing "Duplicate migration" error on fresh database setup.

## [1.0.0] - 2026-03-26

### Breaking Changes

Tracebook is now a layer on top of **RubyLLM** instead of a standalone interaction recorder. It reads from the host app's Chat and Message models (provided by RubyLLM's `acts_as_chat` / `acts_as_message`) and adds cost tracking and review workflow.

**Removed tables:**
- `tracebook_interactions` — RubyLLM's Message model stores conversation data
- `tracebook_rollups_dailies` — aggregates computed live from messages

**New tables:**
- `tracebook_message_costs` — cost and latency per message (polymorphic join to host Message)
- `tracebook_chat_reviews` — review state per chat (polymorphic join to host Chat)

**Updated tables:**
- `tracebook_comments` — FK changed from `interaction_id` to `chat_review_id`

**Removed code:**
- `Interaction`, `LlmSession`, `RollupDaily` models
- `PersistInteractionJob`, `DailyRollupsJob`, `ExportJob`
- `TraceBook.record!` API — replaced by `Tracebook.calculate_cost!(message, provider:, model:)`
- `NormalizedInteraction`, `Mappers`, `RedactionPipeline`, `Result`
- `Adapters::RubyLLM`, `Adapters::ActiveAgent` notification subscribers
- `ActorsController`, `InteractionsController`, `ExportsController`
- `/tracebook/actors/*` and `/tracebook/interactions/*` routes

**New code:**
- `MessageCost` model — stores cost per message
- `ChatReview` model — stores review state per chat
- `ChatsController` — dashboard at `/tracebook/chats`
- `Tracebook.calculate_cost!` — calculates and stores cost for a message
- `config.chat_class` / `config.message_class` — configure host app model names

**Migration guide:**
1. Run `bin/rails tracebook:install:migrations && bin/rails db:migrate`
2. Replace `Tracebook.record!` calls with `Tracebook.calculate_cost!`
3. Update `config/initializers/tracebook.rb` to set `chat_class` and `message_class`
4. Mount the engine: `mount Tracebook::Engine => "/tracebook"`

### Fixed

- **Pricing Calculator**: `matching_rule` now correctly prefers the most specific glob pattern and most recent `effective_from` date.

## [0.1.1] - 2025-12-16

### Added

- **Install Generator**: `bin/rails generate tracebook:install` for simplified setup
- **Pagination**: UI pagination for interactions list using Pagy

### Fixed

- **Root Route**: Added missing root route redirect to `/interactions`
- **Payload Keys**: Fixed `build_normalized_interaction` using wrong keys for payloads

### Changed

- **Documentation**: Clarified that encryption is optional, added setup instructions for users who want to enable it

## [0.1.0] - 2025-11-12

### Added

- **Core Engine**: Rails 8.1+ mountable engine with isolated namespace
- **Recording API**: `TraceBook.record!` for capturing LLM interactions
- **Models**: Interaction, PricingRule, RollupDaily
- **Cost Tracking**: Pricing calculator with configurable rules per provider/model
- **Background Jobs**: PersistInteractionJob, DailyRollupsJob, ExportJob
- **Web UI**: Dashboard with filtering, review workflow, KPI display
- **Adapters**: Integration adapters for RubyLLM and ActiveAgent
- **PII Redaction**: Pre-persist redaction pipeline

[1.1.0]: https://github.com/dpaluy/tracebook/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/dpaluy/tracebook/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/dpaluy/tracebook/compare/v0.1.1...v1.0.0
[0.1.1]: https://github.com/dpaluy/tracebook/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/dpaluy/tracebook/releases/tag/v0.1.0

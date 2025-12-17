# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- **Provider Support**: Mappers for OpenAI, Anthropic, and Ollama APIs
- **Adapters**: Integration adapters for ActiveAgent and RubyLLM libraries
- **Recording API**: `TraceBook.record!` for capturing LLM interactions
- **Configuration**: Flexible `TraceBook.config` with authorization hooks
- **Models**:
  - `Interaction` - Core model for storing LLM call data
  - `PricingRule` - Cost calculation rules per model
  - `RedactionRule` - Custom PII pattern definitions
  - `RollupDaily` - Aggregated daily metrics
- **PII Redaction**: Pre-persist redaction pipeline with built-in redactors:
  - Email addresses
  - Phone numbers
  - Credit card PANs
- **Cost Tracking**: Pricing calculator with configurable rules per provider/model
- **Background Jobs**:
  - `PersistInteractionJob` - Async ingestion pipeline
  - `DailyRollupsJob` - Nightly metric aggregation
  - `ExportJob` - Async data export
- **Web UI**: Turbo + Stimulus dashboard with:
  - Interaction list with filtering (provider, model, date range, review state)
  - Detail view with formatted request/response payloads
  - Review workflow (pending → approved/flagged/rejected)
  - KPI display (token counts, costs, latency)
- **Export**: CSV and NDJSON export capabilities
- **Normalized Schema**: Consistent data structure across all providers
- **Test Suite**: Full MiniTest coverage for models, controllers, jobs, and lib

[0.1.1]: https://github.com/dpaluy/tracebook/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/dpaluy/tracebook/releases/tag/v0.1.0

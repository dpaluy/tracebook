# frozen_string_literal: true

require "csv"

module Tracebook
  # Background job for exporting interactions to CSV or NDJSON.
  #
  # Streams filtered interactions to an export file stored in ActiveStorage.
  # Supports filtering by provider, model, project, date range, tags, etc.
  #
  # ## Supported Formats
  # - **CSV** - Comma-separated values with headers
  # - **NDJSON** - Newline-delimited JSON (one interaction per line)
  #
  # ## Exported Fields
  # - timestamp, project, provider, model, status
  # - input_tokens, output_tokens, cost_total_cents
  # - tags (pipe-separated)
  # - request_payload, response_payload (JSON)
  # - metadata
  #
  # @example Enqueue export job
  #   blob = ExportJob.perform_now(
  #     format: :csv,
  #     filters: {
  #       provider: "openai",
  #       from: 30.days.ago,
  #       to: Date.current
  #     }
  #   )
  #   download_url = Rails.application.routes.url_helpers.rails_blob_url(blob)
  #
  # @example Export specific project
  #   ExportJob.perform_later(
  #     format: :ndjson,
  #     filters: { project: "support", review_state: "approved" }
  #   )
  #
  # @see Interaction.filtered
  class ExportJob < ApplicationJob
    # Exports filtered interactions to specified format.
    #
    # @param format [Symbol, String] Export format (:csv or :ndjson)
    # @param filters [Hash] Filters to apply (see {Interaction.filtered})
    #
    # @option filters [String] :provider Provider name
    # @option filters [String] :model Model identifier
    # @option filters [String] :project Project name
    # @option filters [Symbol, String] :status Status filter
    # @option filters [Symbol, String] :review_state Review state filter
    # @option filters [String] :tag Tag to filter by
    # @option filters [Date, String] :from Start date
    # @option filters [Date, String] :to End date
    #
    # @return [ActiveStorage::Blob] The created export blob
    #
    # @raise [ArgumentError] if format is not supported
    def perform(format:, filters: {})
      interactions = Interaction.filtered(filters).order(:created_at)
      data = export_as(interactions, format.to_sym)
      create_blob(data, format)
    end

    private

    def export_as(interactions, format)
      case format
      when :csv
        csv_for(interactions)
      when :ndjson
        ndjson_for(interactions)
      else
        raise ArgumentError, "Unsupported export format: #{format}"
      end
    end

    def csv_for(interactions)
      CSV.generate do |csv|
        csv << csv_headers
        interactions.find_each do |interaction|
          csv << serialize_interaction(interaction).values_at(*csv_headers)
        end
      end
    end

    def ndjson_for(interactions)
      Enumerator.new do |yielder|
        interactions.find_each do |interaction|
          yielder << serialize_interaction(interaction).to_json
        end
      end.to_a.join("\n")
    end

    def serialize_interaction(interaction)
      payload = {
        "timestamp" => interaction.created_at.iso8601,
        "project" => interaction.project,
        "provider" => interaction.provider,
        "model" => interaction.model,
        "status" => interaction.status,
        "input_tokens" => interaction.input_tokens,
        "output_tokens" => interaction.output_tokens,
        "cost_total_cents" => interaction.cost_total_cents,
        "tags" => Array(interaction.tags).join("|"),
        "request_payload" => load_payload(interaction, :request),
        "response_payload" => load_payload(interaction, :response)
      }

      payload.merge("metadata" => interaction.metadata)
    end

    def load_payload(interaction, type)
      store = interaction.public_send("#{type}_payload_store")
      if store == "active_storage"
        blob = interaction.public_send("#{type}_payload_blob")
        return JSON.parse(blob.download) if blob
      end

      interaction.public_send("#{type}_payload")
    rescue JSON::ParserError
      interaction.public_send("#{type}_payload")
    end

    def create_blob(data, format)
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(data),
        filename: "tracebook-export-#{Time.current.to_i}.#{format}",
        content_type: content_type_for(format)
      )
    end

    def content_type_for(format)
      case format.to_sym
      when :csv
        "text/csv"
      when :ndjson
        "application/x-ndjson"
      else
        "application/octet-stream"
      end
    end

    def csv_headers
      @csv_headers ||= [
        "timestamp",
        "project",
        "provider",
        "model",
        "status",
        "input_tokens",
        "output_tokens",
        "cost_total_cents",
        "tags",
        "request_payload",
        "response_payload",
        "metadata"
      ]
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)

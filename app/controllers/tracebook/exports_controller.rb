# frozen_string_literal: true

module Tracebook
  class ExportsController < ApplicationController
    def create
      blob = ExportJob.perform_now(format: params.fetch(:format, :csv), filters: export_filters)
      redirect_to export_path(blob.signed_id), notice: "Export ready"
    end

    def show
      blob = ActiveStorage::Blob.find_signed!(params[:id])
      send_data blob.download, filename: blob.filename.to_s, type: blob.content_type
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
      head :not_found
    end

    private

    def export_filters
      params.fetch(:filters, {}).permit(:provider, :model, :project, :status, :review_state, :from, :to)
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)

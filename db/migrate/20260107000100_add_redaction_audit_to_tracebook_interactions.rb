# frozen_string_literal: true

class AddRedactionAuditToTracebookInteractions < ActiveRecord::Migration[8.1]
  def change
    add_column :tracebook_interactions, :redaction_audit, :text
  end
end

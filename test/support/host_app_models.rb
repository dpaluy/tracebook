# frozen_string_literal: true

connection = ActiveRecord::Base.connection

unless connection.data_source_exists?(:tracebook_test_models)
  connection.create_table :tracebook_test_models do |t|
    t.string :model_id, null: false

    t.timestamps
  end
end

unless connection.data_source_exists?(:tracebook_test_chats)
  connection.create_table :tracebook_test_chats do |t|
    t.timestamps
  end
end

unless connection.data_source_exists?(:tracebook_test_messages)
  connection.create_table :tracebook_test_messages do |t|
    t.references :chat, null: false, foreign_key: { to_table: :tracebook_test_chats }
    t.references :model, foreign_key: { to_table: :tracebook_test_models }
    t.string :role, null: false
    t.integer :input_tokens
    t.integer :output_tokens
    t.text :content

    t.timestamps
  end
end

class TracebookTestModel < ApplicationRecord
  self.table_name = "tracebook_test_models"
end

class TracebookTestChat < ApplicationRecord
  self.table_name = "tracebook_test_chats"

  has_many :messages, class_name: "TracebookTestMessage", foreign_key: :chat_id, inverse_of: :chat, dependent: :delete_all
end

class TracebookTestMessage < ApplicationRecord
  self.table_name = "tracebook_test_messages"

  belongs_to :chat, class_name: "TracebookTestChat", inverse_of: :messages
  belongs_to :model, class_name: "TracebookTestModel", optional: true
end

module TracebookTestHostApp
  def configure_tracebook_test_host!
    TraceBook.reset_configuration!
    TraceBook.configure do |config|
      config.chat_class = "TracebookTestChat"
      config.message_class = "TracebookTestMessage"
    end
  end

  def clear_tracebook_test_data!
    Tracebook::Comment.delete_all
    Tracebook::ChatReview.delete_all
    Tracebook::MessageCost.delete_all
    Tracebook::PricingRule.delete_all
    TracebookTestMessage.delete_all
    TracebookTestChat.delete_all
    TracebookTestModel.delete_all
  end
end

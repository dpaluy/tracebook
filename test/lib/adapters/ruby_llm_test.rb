# frozen_string_literal: true

require "test_helper"

module Tracebook
  module Adapters
    class RubyLLMTest < ActiveSupport::TestCase
      teardown do
        Object.send(:remove_const, :RubyLLM) if defined?(::RubyLLM)
        Object.send(:remove_const, @test_const) if @test_const && Object.const_defined?(@test_const)
      end

      test "enable! raises LoadError when RubyLLM is not defined" do
        assert_raises(LoadError) { RubyLLM.enable! }
      end

      test "enable! includes CostTracking concern in configured message class" do
        define_fake_ruby_llm
        klass = register_test_class
        configure_with_message_class(@test_const)

        refute klass.include?(RubyLLM::CostTracking)
        RubyLLM.enable!
        assert klass.include?(RubyLLM::CostTracking)
      end

      test "enable! is idempotent when called multiple times" do
        define_fake_ruby_llm
        register_test_class
        configure_with_message_class(@test_const)

        assert_nothing_raised do
          RubyLLM.enable!
          RubyLLM.enable!
        end
      end

      test "tracebook_calculate_cost rescues StandardError and logs" do
        define_fake_ruby_llm(models_raise: true)

        msg = Object.new
        msg.define_singleton_method(:id) { 999 }
        msg.define_singleton_method(:chat) { OpenStruct.new(model_id: "gpt-4o") }
        msg.extend(RubyLLM::CostTracking)

        assert_nothing_raised do
          msg.send(:tracebook_calculate_cost)
        end
      end

      private

      def define_fake_ruby_llm(models_raise: false)
        Object.const_set(:RubyLLM, Module.new) unless defined?(::RubyLLM)

        unless defined?(::RubyLLM::Models)
          models_mod = if models_raise
            Module.new do
              def self.find(_model_id)
                raise ArgumentError, "unknown model"
              end
            end
          else
            Module.new do
              def self.find(_model_id)
                OpenStruct.new(provider: "openai")
              end
            end
          end
          ::RubyLLM.const_set(:Models, models_mod)
        end
      end

      def register_test_class
        klass = Class.new(ApplicationRecord) { self.table_name = "tracebook_test_messages" }
        @test_const = :"TracebookAdapterTest#{SecureRandom.hex(4).upcase}"
        Object.const_set(@test_const, klass)
        klass
      end

      def configure_with_message_class(name)
        Tracebook.reset_configuration!
        Tracebook.configure do |config|
          config.chat_class = "TracebookTestChat"
          config.message_class = name.to_s
        end
      end
    end
  end
end

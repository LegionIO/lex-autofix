# frozen_string_literal: true

require 'spec_helper'

unless defined?(Legion::Extensions::Actors::Subscription)
  module Legion
    module Extensions
      module Actors
        class Subscription; end # rubocop:disable Lint/EmptyClass
      end
    end
  end
end

require 'legion/extensions/autofix/actors/log_consumer'

RSpec.describe Legion::Extensions::Autofix::Actor::LogConsumer do
  subject(:actor) { described_class.allocate }

  describe '#runner_function' do
    it 'returns handle_log_event' do
      expect(actor.runner_function).to eq('handle_log_event')
    end
  end

  describe '#check_subtask?' do
    it 'returns true' do
      expect(actor.check_subtask?).to be(true)
    end
  end

  describe '#generate_task?' do
    it 'returns false' do
      expect(actor.generate_task?).to be(false)
    end
  end

  describe '#enabled?' do
    context 'when Legion::LLM is defined and started? returns true' do
      before do
        stub_const('Legion::LLM', Module.new do
          def self.started? = true
        end)
      end

      it 'returns true' do
        expect(actor.enabled?).to be(true)
      end
    end

    context 'when Legion::LLM is defined but started? returns false' do
      before do
        stub_const('Legion::LLM', Module.new do
          def self.started? = false
        end)
      end

      it 'returns false' do
        expect(actor.enabled?).to be(false)
      end
    end

    context 'when Legion::LLM is not defined' do
      before { hide_const('Legion::LLM') }

      it 'returns false' do
        expect(actor.enabled?).to be(false)
      end
    end
  end
end

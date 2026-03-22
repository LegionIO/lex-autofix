# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/autofix/runners/triage'

RSpec.describe Legion::Extensions::Autofix::Runners::Triage do
  subject(:host) { Object.new.extend(described_class) }

  let(:events) do
    [
      { lex: 'lex-foo', exception_class: 'RuntimeError', message: 'boom' },
      { lex: 'lex-bar', exception_class: 'ArgumentError', message: 'bad arg' }
    ]
  end

  let(:actionable_cluster) do
    { id: 'c1', summary: 'RuntimeError in lex-foo', actionable: true, events: [0] }
  end

  let(:non_actionable_cluster) do
    { id: 'c2', summary: 'ArgumentError in lex-bar', actionable: false, events: [1] }
  end

  let(:llm_response) do
    { clusters: [actionable_cluster, non_actionable_cluster] }
  end

  before do
    stub_const('Legion::LLM', Module.new { def self.structured(**); end })
    allow(Legion::LLM).to receive(:structured).and_return(llm_response)
  end

  describe '#batch_triage' do
    context 'when events array is empty' do
      it 'returns failure with reason' do
        result = host.batch_triage(events: [])
        expect(result[:success]).to be(false)
        expect(result[:reason]).to eq('no events to triage')
      end
    end

    context 'when LLM returns clusters' do
      it 'returns success: true' do
        result = host.batch_triage(events: events)
        expect(result[:success]).to be(true)
      end

      it 'includes all clusters in result' do
        result = host.batch_triage(events: events)
        expect(result[:clusters]).to eq([actionable_cluster, non_actionable_cluster])
      end

      it 'partitions actionable clusters' do
        result = host.batch_triage(events: events)
        expect(result[:actionable]).to eq([actionable_cluster])
      end

      it 'partitions non_actionable clusters' do
        result = host.batch_triage(events: events)
        expect(result[:non_actionable]).to eq([non_actionable_cluster])
      end

      it 'calls Legion::LLM.structured with a user message and schema' do
        host.batch_triage(events: events)
        expect(Legion::LLM).to have_received(:structured) do |args|
          messages = args[:messages]
          expect(messages.length).to eq(1)
          expect(messages.first[:role]).to eq('user')
          expect(args[:schema]).to be_a(Hash)
        end
      end
    end

    context 'when LLM raises an exception' do
      before do
        allow(Legion::LLM).to receive(:structured).and_raise(StandardError, 'LLM unavailable')
      end

      it 'returns success: false' do
        result = host.batch_triage(events: events)
        expect(result[:success]).to be(false)
      end

      it 'returns the exception message as reason' do
        result = host.batch_triage(events: events)
        expect(result[:reason]).to eq('LLM unavailable')
      end
    end
  end
end

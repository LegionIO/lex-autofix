# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/autofix/runners/pipeline'

RSpec.describe Legion::Extensions::Autofix::Runners::Pipeline do
  subject(:host) { Object.new.extend(described_class) }

  let(:buffer) do
    instance_double(
      Legion::Extensions::Autofix::Helpers::BatchBuffer,
      add:          nil,
      flush_ready?: false,
      flush!:       []
    )
  end

  let(:token) { 'ghp_test_token' }
  let(:org)   { 'LegionIO' }

  let(:actionable_cluster) do
    {
      id:             'c1',
      summary:        'RuntimeError in lex-foo',
      actionable:     true,
      suggested_repo: 'lex-foo',
      diagnosis:      'Unhandled RuntimeError'
    }
  end

  let(:non_actionable_cluster) do
    {
      id:         'c2',
      summary:    'ArgumentError in lex-bar',
      actionable: false
    }
  end

  let(:events) do
    [
      { lex: 'lex-foo', exception_class: 'RuntimeError', message: 'boom',
        caller_file: 'lib/lex/foo/runner.rb', caller_line: 42 },
      { lex: 'lex-bar', exception_class: 'ArgumentError', message: 'bad arg',
        caller_file: 'lib/lex/bar/runner.rb', caller_line: 10 }
    ]
  end

  before do
    stub_const('Legion::LLM', Module.new { def self.structured(**); end })
    stub_const('Legion::Extensions::Github::Client', Class.new do
      def initialize(token:); end

      def search_issues(query:); end

      def create_issue(owner:, repo:, title:, body:, labels:); end

      def create_comment(owner:, repo:, issue_number:, body:); end

      def create_pull_request(owner:, repo:, title:, head:, base:, body:); end # rubocop:disable Metrics/ParameterLists
    end)

    described_class.instance_variable_set(:@buffer, buffer)
  end

  after do
    described_class.instance_variable_set(:@buffer, nil)
  end

  describe '.buffer' do
    after { described_class.instance_variable_set(:@buffer, nil) }

    context 'when Legion::Settings is not defined' do
      before { hide_const('Legion::Settings') }

      it 'creates a BatchBuffer with default settings' do
        described_class.instance_variable_set(:@buffer, nil)
        result = described_class.buffer
        expect(result).to be_a(Legion::Extensions::Autofix::Helpers::BatchBuffer)
      end
    end

    context 'when Legion::Settings is defined with custom values' do
      before do
        stub_const('Legion::Settings', Module.new do
          def self.dig(*_keys)
            nil
          end
        end)
        described_class.instance_variable_set(:@buffer, nil)
      end

      it 'returns a BatchBuffer instance' do
        expect(described_class.buffer).to be_a(Legion::Extensions::Autofix::Helpers::BatchBuffer)
      end
    end

    context 'when already initialized' do
      it 'returns the same buffer instance' do
        expect(described_class.buffer).to be(buffer)
      end
    end
  end

  describe '#handle_log_event' do
    let(:event) { { lex: 'lex-foo', exception_class: 'RuntimeError', message: 'boom' } }

    it 'adds the event to the buffer' do
      host.handle_log_event(**event)
      expect(buffer).to have_received(:add).with(event)
    end

    it 'returns success: true' do
      result = host.handle_log_event(**event)
      expect(result[:success]).to be(true)
    end

    context 'when flush_ready? is false' do
      before { allow(buffer).to receive(:flush_ready?).and_return(false) }

      it 'does not call run_pipeline' do
        allow(host).to receive(:run_pipeline)
        host.handle_log_event(**event)
        expect(host).not_to have_received(:run_pipeline)
      end
    end

    context 'when flush_ready? is true' do
      before do
        allow(buffer).to receive(:flush_ready?).and_return(true)
        allow(buffer).to receive(:flush!).and_return([event])
        allow(Legion::LLM).to receive(:structured).and_return({ clusters: [] })
      end

      it 'calls run_pipeline' do
        allow(host).to receive(:run_pipeline).and_return({ success: true })
        host.handle_log_event(**event)
        expect(host).to have_received(:run_pipeline)
      end
    end
  end

  describe '#run_pipeline' do
    before do
      allow(buffer).to receive(:flush!).and_return(events)
    end

    context 'when triage succeeds with actionable and non-actionable clusters' do
      before do
        allow(host).to receive(:batch_triage).and_return(
          success:        true,
          clusters:       [actionable_cluster, non_actionable_cluster],
          actionable:     [actionable_cluster],
          non_actionable: [non_actionable_cluster]
        )
        allow(host).to receive(:process_cluster).and_return({ success: true })
      end

      it 'returns success: true' do
        result = host.run_pipeline
        expect(result[:success]).to be(true)
      end

      it 'calls process_cluster for each actionable cluster' do
        host.run_pipeline
        expect(host).to have_received(:process_cluster).once
      end

      it 'does not call process_cluster for non-actionable clusters' do
        host.run_pipeline
        expect(host).to have_received(:process_cluster).with(
          hash_including(cluster: actionable_cluster)
        )
      end
    end

    context 'when triage returns no clusters' do
      before do
        allow(host).to receive(:batch_triage).and_return(
          success: true, clusters: [], actionable: [], non_actionable: []
        )
        allow(host).to receive(:process_cluster)
      end

      it 'returns success: true' do
        result = host.run_pipeline
        expect(result[:success]).to be(true)
      end

      it 'does not call process_cluster' do
        host.run_pipeline
        expect(host).not_to have_received(:process_cluster)
      end
    end

    context 'when triage fails' do
      before do
        allow(host).to receive(:batch_triage).and_return(
          success: false, reason: 'LLM unavailable'
        )
        allow(host).to receive(:process_cluster)
      end

      it 'returns the triage failure result' do
        result = host.run_pipeline
        expect(result[:success]).to be(false)
        expect(result[:reason]).to eq('LLM unavailable')
      end

      it 'does not call process_cluster' do
        host.run_pipeline
        expect(host).not_to have_received(:process_cluster)
      end
    end
  end

  describe '#process_cluster' do
    let(:fix_checkout_path) { '/tmp/autofix/checkout_abc' }

    before do
      stub_const('Legion::Settings', Module.new do
        def self.dig(*_keys)
          nil
        end
      end)
    end

    context 'when check_github fails' do
      before do
        allow(host).to receive(:check_github).and_return({ success: false, reason: 'API error' })
      end

      it 'returns the github failure result' do
        result = host.process_cluster(cluster: actionable_cluster, events: events)
        expect(result[:success]).to be(false)
        expect(result[:reason]).to eq('API error')
      end

      it 'does not call attempt_fix' do
        allow(host).to receive(:attempt_fix)
        host.process_cluster(cluster: actionable_cluster, events: events)
        expect(host).not_to have_received(:attempt_fix)
      end
    end

    context 'when check_github returns action: :skipped' do
      before do
        allow(host).to receive(:check_github).and_return(
          { success: true, action: :skipped, issue_number: 5 }
        )
      end

      it 'returns success: true with action: :issue_only' do
        result = host.process_cluster(cluster: actionable_cluster, events: events)
        expect(result[:success]).to be(true)
        expect(result[:action]).to eq(:issue_only)
      end

      it 'does not call attempt_fix' do
        allow(host).to receive(:attempt_fix)
        host.process_cluster(cluster: actionable_cluster, events: events)
        expect(host).not_to have_received(:attempt_fix)
      end
    end

    context 'when check_github succeeds with action: :created and fix succeeds' do
      before do
        allow(host).to receive(:check_github).and_return(
          { success: true, action: :created, issue_number: 7 }
        )
        allow(host).to receive(:attempt_fix).and_return(
          { success: true, checkout_path: fix_checkout_path }
        )
        allow(host).to receive(:ship).and_return(
          { success: true, pr_number: 99, url: 'https://github.com/LegionIO/lex-foo/pull/99' }
        )
      end

      it 'returns success: true' do
        result = host.process_cluster(cluster: actionable_cluster, events: events)
        expect(result[:success]).to be(true)
      end

      it 'calls attempt_fix with the correct repo_url and branch' do
        host.process_cluster(cluster: actionable_cluster, events: events)
        expect(host).to have_received(:attempt_fix) do |args|
          expect(args[:repo_url]).to eq('https://github.com/LegionIO/lex-foo.git')
          expect(args[:branch]).to start_with('autofix/7-')
        end
      end

      it 'calls ship with the checkout_path from attempt_fix' do
        host.process_cluster(cluster: actionable_cluster, events: events)
        expect(host).to have_received(:ship) do |args|
          expect(args[:checkout_path]).to eq(fix_checkout_path)
          expect(args[:issue_number]).to eq(7)
          expect(args[:repo]).to eq('lex-foo')
          expect(args[:owner]).to eq('LegionIO')
        end
      end
    end

    context 'when check_github succeeds but fix fails' do
      before do
        allow(host).to receive(:check_github).and_return(
          { success: true, action: :created, issue_number: 7 }
        )
        allow(host).to receive(:attempt_fix).and_return(
          { success: false, reason: 'fix failed after max retries (3)' }
        )
        allow(host).to receive(:ship)
      end

      it 'returns the fix failure result' do
        result = host.process_cluster(cluster: actionable_cluster, events: events)
        expect(result[:success]).to be(false)
        expect(result[:reason]).to eq('fix failed after max retries (3)')
      end

      it 'does not call ship' do
        host.process_cluster(cluster: actionable_cluster, events: events)
        expect(host).not_to have_received(:ship)
      end
    end
  end

  describe '#slug' do
    it 'lowercases the text' do
      expect(host.send(:slug, 'RuntimeError In Foo')).to eq('runtimeerror-in-foo')
    end

    it 'replaces non-alphanumeric characters with hyphens' do
      expect(host.send(:slug, 'foo::bar baz')).to eq('foo-bar-baz')
    end

    it 'truncates to 40 characters' do
      long = 'a' * 50
      expect(host.send(:slug, long).length).to eq(40)
    end

    it 'strips trailing hyphens after truncation' do
      text = "#{'a' * 39}!!!"
      result = host.send(:slug, text)
      expect(result).not_to end_with('-')
    end

    it 'handles nil gracefully' do
      expect(host.send(:slug, nil)).to eq('')
    end
  end
end

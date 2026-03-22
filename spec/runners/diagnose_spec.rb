# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/autofix/runners/diagnose'

RSpec.describe Legion::Extensions::Autofix::Runners::Diagnose do
  subject(:host) { Object.new.extend(described_class) }

  let(:token) { 'ghp_test_token' }
  let(:org)   { 'LegionIO' }

  let(:cluster) do
    {
      suggested_repo: 'lex-foo',
      summary:        'RuntimeError in lex-foo worker',
      diagnosis:      'Unhandled RuntimeError during task processing'
    }
  end

  let(:events) do
    [
      {
        exception_class: 'RuntimeError',
        message:         'something exploded',
        caller_file:     'lib/lex/foo/runner.rb',
        caller_line:     42,
        first_seen:      '2026-03-21T00:00:00Z',
        backtrace:       [
          'lib/lex/foo/runner.rb:42:in `run`',
          'lib/lex/foo/actor.rb:10:in `call`',
          'lib/legion/extensions/core.rb:88:in `dispatch`',
          'lib/legion/extensions/core.rb:55:in `execute`',
          'lib/legion.rb:120:in `start`'
        ]
      },
      {
        exception_class: 'RuntimeError',
        message:         'something exploded again',
        caller_file:     'lib/lex/foo/runner.rb',
        caller_line:     99,
        first_seen:      '2026-03-21T00:01:00Z',
        backtrace:       []
      }
    ]
  end

  let(:github_client) do
    instance_double(Legion::Extensions::Github::Client,
                    search_issues:  { result: { items: [] } },
                    create_issue:   { result: { number: 7, html_url: 'https://github.com/LegionIO/lex-foo/issues/7' } },
                    create_comment: { result: { id: 99 } })
  end

  before do
    stub_const('Legion::Extensions::Github::Client', Class.new do
      def initialize(token:); end

      def search_issues(query:); end

      def create_issue(owner:, repo:, title:, body:, labels:); end

      def create_comment(owner:, repo:, issue_number:, body:); end
    end)
    allow(Legion::Extensions::Github::Client).to receive(:new).with(token: token).and_return(github_client)
  end

  describe '#check_github' do
    context 'when no matching issue exists' do
      before do
        allow(github_client).to receive(:search_issues).and_return({ result: { items: [] } })
      end

      it 'returns success: true' do
        result = host.check_github(cluster: cluster, events: events, token: token, org: org)
        expect(result[:success]).to be(true)
      end

      it 'returns action: :created' do
        result = host.check_github(cluster: cluster, events: events, token: token, org: org)
        expect(result[:action]).to eq(:created)
      end

      it 'returns the issue number from the API response' do
        result = host.check_github(cluster: cluster, events: events, token: token, org: org)
        expect(result[:issue_number]).to eq(7)
      end

      it 'returns the issue url from the API response' do
        result = host.check_github(cluster: cluster, events: events, token: token, org: org)
        expect(result[:url]).to eq('https://github.com/LegionIO/lex-foo/issues/7')
      end

      it 'calls create_issue with the autofix label and structured body' do
        host.check_github(cluster: cluster, events: events, token: token, org: org)
        expect(github_client).to have_received(:create_issue) do |args|
          expect(args[:owner]).to eq(org)
          expect(args[:repo]).to eq('lex-foo')
          expect(args[:title]).to eq('autofix: RuntimeError in lex-foo worker')
          expect(args[:labels]).to eq(['autofix'])
          expect(args[:body]).to include('RuntimeError')
          expect(args[:body]).to include('lib/lex/foo/runner.rb:42')
        end
      end

      it 'searches with the correct query' do
        host.check_github(cluster: cluster, events: events, token: token, org: org)
        expect(github_client).to have_received(:search_issues).with(
          query: 'repo:LegionIO/lex-foo is:open label:autofix RuntimeError'
        )
      end
    end

    context 'when a matching issue exists and all caller locations are already in the body' do
      let(:existing_body) do
        "lib/lex/foo/runner.rb:42\nlib/lex/foo/runner.rb:99"
      end

      let(:existing_issue) do
        { number: 3, body: existing_body }
      end

      before do
        allow(github_client).to receive(:search_issues).and_return(
          { result: { items: [existing_issue] } }
        )
      end

      it 'returns success: true' do
        result = host.check_github(cluster: cluster, events: events, token: token, org: org)
        expect(result[:success]).to be(true)
      end

      it 'returns action: :skipped' do
        result = host.check_github(cluster: cluster, events: events, token: token, org: org)
        expect(result[:action]).to eq(:skipped)
      end

      it 'returns the existing issue number' do
        result = host.check_github(cluster: cluster, events: events, token: token, org: org)
        expect(result[:issue_number]).to eq(3)
      end

      it 'does not call create_comment' do
        host.check_github(cluster: cluster, events: events, token: token, org: org)
        expect(github_client).not_to have_received(:create_comment)
      end

      it 'does not call create_issue' do
        host.check_github(cluster: cluster, events: events, token: token, org: org)
        expect(github_client).not_to have_received(:create_issue)
      end
    end

    context 'when a matching issue exists but has new caller locations' do
      let(:existing_body) do
        'lib/lex/foo/runner.rb:42'
      end

      let(:existing_issue) do
        { number: 5, body: existing_body }
      end

      before do
        allow(github_client).to receive(:search_issues).and_return(
          { result: { items: [existing_issue] } }
        )
      end

      it 'returns success: true' do
        result = host.check_github(cluster: cluster, events: events, token: token, org: org)
        expect(result[:success]).to be(true)
      end

      it 'returns action: :commented' do
        result = host.check_github(cluster: cluster, events: events, token: token, org: org)
        expect(result[:action]).to eq(:commented)
      end

      it 'returns the existing issue number' do
        result = host.check_github(cluster: cluster, events: events, token: token, org: org)
        expect(result[:issue_number]).to eq(5)
      end

      it 'posts a comment with the new caller location' do
        host.check_github(cluster: cluster, events: events, token: token, org: org)
        expect(github_client).to have_received(:create_comment) do |args|
          expect(args[:owner]).to eq(org)
          expect(args[:repo]).to eq('lex-foo')
          expect(args[:issue_number]).to eq(5)
          expect(args[:body]).to include('lib/lex/foo/runner.rb:99')
          expect(args[:body]).not_to include('lib/lex/foo/runner.rb:42')
        end
      end

      it 'does not call create_issue' do
        host.check_github(cluster: cluster, events: events, token: token, org: org)
        expect(github_client).not_to have_received(:create_issue)
      end
    end

    context 'when the GitHub API raises an error' do
      before do
        allow(github_client).to receive(:search_issues).and_raise(StandardError, 'API rate limit exceeded')
      end

      it 'returns success: false' do
        result = host.check_github(cluster: cluster, events: events, token: token, org: org)
        expect(result[:success]).to be(false)
      end

      it 'returns the exception message as reason' do
        result = host.check_github(cluster: cluster, events: events, token: token, org: org)
        expect(result[:reason]).to eq('API rate limit exceeded')
      end
    end
  end
end

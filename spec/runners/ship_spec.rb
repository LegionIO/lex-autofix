# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/autofix/runners/ship'

RSpec.describe Legion::Extensions::Autofix::Runners::Ship do
  subject(:host) { Object.new.extend(described_class) }

  let(:checkout_path) { '/tmp/autofix_test/checkout_abc123' }
  let(:branch)        { 'autofix/runtime-error' }
  let(:owner)         { 'LegionIO' }
  let(:repo)          { 'lex-foo' }
  let(:issue_number)  { 42 }
  let(:summary)       { 'fix RuntimeError in worker' }
  let(:token)         { 'ghp_test_token' }

  let(:github_client) do
    instance_double(Legion::Extensions::Github::Client,
                    create_pull_request: { result: { number: 99, html_url: 'https://github.com/LegionIO/lex-foo/pull/99' } })
  end

  let(:tc) do
    instance_double(Legion::Extensions::Autofix::Helpers::TempCheckout, cleanup: { success: true })
  end

  before do
    stub_const('Legion::Extensions::Github::Client', Class.new do
      def initialize(token:); end

      def create_pull_request(owner:, repo:, title:, head:, base:, body:); end
    end)
    allow(Legion::Extensions::Github::Client).to receive(:new).with(token: token).and_return(github_client)
    allow(Legion::Extensions::Autofix::Helpers::TempCheckout).to receive(:new).and_return(tc)
  end

  describe '#commit_and_push' do
    context 'when all git commands succeed' do
      before do
        allow(Dir).to receive(:chdir).with(checkout_path).and_yield
        allow(host).to receive(:system).and_return(true)
      end

      it 'returns success: true' do
        result = host.commit_and_push(checkout_path: checkout_path, branch: branch, message: 'fix: boom')
        expect(result[:success]).to be(true)
      end

      it 'runs git add -A' do
        host.commit_and_push(checkout_path: checkout_path, branch: branch, message: 'fix: boom')
        expect(host).to have_received(:system).with('git', 'add', '-A')
      end

      it 'runs git commit with the message' do
        host.commit_and_push(checkout_path: checkout_path, branch: branch, message: 'fix: boom')
        expect(host).to have_received(:system).with('git', 'commit', '-m', 'fix: boom')
      end

      it 'runs git push -u origin branch' do
        host.commit_and_push(checkout_path: checkout_path, branch: branch, message: 'fix: boom')
        expect(host).to have_received(:system).with('git', 'push', '-u', 'origin', branch)
      end
    end

    context 'when git add fails' do
      before do
        allow(Dir).to receive(:chdir).with(checkout_path).and_yield
        allow(host).to receive(:system).with('git', 'add', '-A').and_return(false)
      end

      it 'returns success: false' do
        result = host.commit_and_push(checkout_path: checkout_path, branch: branch, message: 'fix: boom')
        expect(result[:success]).to be(false)
      end

      it 'returns the add failure reason' do
        result = host.commit_and_push(checkout_path: checkout_path, branch: branch, message: 'fix: boom')
        expect(result[:reason]).to eq('git add failed')
      end
    end

    context 'when git push fails' do
      before do
        allow(Dir).to receive(:chdir).with(checkout_path).and_yield
        allow(host).to receive(:system).with('git', 'add', '-A').and_return(true)
        allow(host).to receive(:system).with('git', 'commit', '-m', anything).and_return(true)
        allow(host).to receive(:system).with('git', 'push', '-u', 'origin', branch).and_return(false)
      end

      it 'returns success: false' do
        result = host.commit_and_push(checkout_path: checkout_path, branch: branch, message: 'fix: boom')
        expect(result[:success]).to be(false)
      end

      it 'returns the push failure reason' do
        result = host.commit_and_push(checkout_path: checkout_path, branch: branch, message: 'fix: boom')
        expect(result[:reason]).to eq('git push failed')
      end
    end
  end

  describe '#open_pr' do
    context 'when the API call succeeds' do
      it 'returns success: true' do
        result = host.open_pr(owner: owner, repo: repo, branch: branch,
                              title: 'fix: boom', body: 'Closes #42', token: token)
        expect(result[:success]).to be(true)
      end

      it 'returns the PR number' do
        result = host.open_pr(owner: owner, repo: repo, branch: branch,
                              title: 'fix: boom', body: 'Closes #42', token: token)
        expect(result[:pr_number]).to eq(99)
      end

      it 'returns the PR url' do
        result = host.open_pr(owner: owner, repo: repo, branch: branch,
                              title: 'fix: boom', body: 'Closes #42', token: token)
        expect(result[:url]).to eq('https://github.com/LegionIO/lex-foo/pull/99')
      end

      it 'calls create_pull_request with correct args' do
        host.open_pr(owner: owner, repo: repo, branch: branch,
                     title: 'fix: boom', body: 'Closes #42', token: token)
        expect(github_client).to have_received(:create_pull_request).with(
          owner: owner,
          repo:  repo,
          title: 'fix: boom',
          head:  branch,
          base:  'main',
          body:  'Closes #42'
        )
      end
    end

    context 'when the API raises an error' do
      before do
        allow(github_client).to receive(:create_pull_request).and_raise(StandardError, 'API error')
      end

      it 'returns success: false' do
        result = host.open_pr(owner: owner, repo: repo, branch: branch,
                              title: 'fix: boom', body: 'Closes #42', token: token)
        expect(result[:success]).to be(false)
      end

      it 'returns the exception message as reason' do
        result = host.open_pr(owner: owner, repo: repo, branch: branch,
                              title: 'fix: boom', body: 'Closes #42', token: token)
        expect(result[:reason]).to eq('API error')
      end
    end
  end

  describe '#ship' do
    context 'when commit_and_push and open_pr both succeed' do
      before do
        allow(host).to receive(:commit_and_push).and_return({ success: true })
        allow(host).to receive(:open_pr).and_return(
          { success: true, pr_number: 99, url: 'https://github.com/LegionIO/lex-foo/pull/99' }
        )
      end

      it 'returns success: true' do
        result = host.ship(checkout_path: checkout_path, owner: owner, repo: repo,
                           branch: branch, issue_number: issue_number, summary: summary, token: token)
        expect(result[:success]).to be(true)
      end

      it 'returns the pr_number' do
        result = host.ship(checkout_path: checkout_path, owner: owner, repo: repo,
                           branch: branch, issue_number: issue_number, summary: summary, token: token)
        expect(result[:pr_number]).to eq(99)
      end

      it 'returns the PR url' do
        result = host.ship(checkout_path: checkout_path, owner: owner, repo: repo,
                           branch: branch, issue_number: issue_number, summary: summary, token: token)
        expect(result[:url]).to eq('https://github.com/LegionIO/lex-foo/pull/99')
      end

      it 'calls commit_and_push with the correct args' do
        host.ship(checkout_path: checkout_path, owner: owner, repo: repo,
                  branch: branch, issue_number: issue_number, summary: summary, token: token)
        expect(host).to have_received(:commit_and_push).with(
          checkout_path: checkout_path,
          branch:        branch,
          message:       "fix: #{summary}"
        )
      end

      it 'calls open_pr with title and body referencing the issue' do
        host.ship(checkout_path: checkout_path, owner: owner, repo: repo,
                  branch: branch, issue_number: issue_number, summary: summary, token: token)
        expect(host).to have_received(:open_pr).with(
          owner:  owner,
          repo:   repo,
          branch: branch,
          title:  "fix: #{summary}",
          body:   "Closes ##{issue_number}\n\nAutomated fix by lex-autofix.",
          token:  token
        )
      end

      it 'cleans up the checkout path' do
        host.ship(checkout_path: checkout_path, owner: owner, repo: repo,
                  branch: branch, issue_number: issue_number, summary: summary, token: token)
        expect(tc).to have_received(:cleanup).with(checkout_path)
      end

      it 'passes checkout_dir to TempCheckout when provided' do
        host.ship(checkout_path: checkout_path, owner: owner, repo: repo,
                  branch: branch, issue_number: issue_number, summary: summary, token: token,
                  checkout_dir: '/tmp/custom')
        expect(Legion::Extensions::Autofix::Helpers::TempCheckout).to have_received(:new)
          .with(base_dir: '/tmp/custom')
      end

      it 'instantiates TempCheckout with no args when checkout_dir is nil' do
        host.ship(checkout_path: checkout_path, owner: owner, repo: repo,
                  branch: branch, issue_number: issue_number, summary: summary, token: token)
        expect(Legion::Extensions::Autofix::Helpers::TempCheckout).to have_received(:new).with(no_args)
      end
    end

    context 'when commit_and_push fails' do
      before do
        allow(host).to receive(:commit_and_push).and_return({ success: false, reason: 'git push failed' })
        allow(host).to receive(:open_pr)
      end

      it 'returns the commit failure result' do
        result = host.ship(checkout_path: checkout_path, owner: owner, repo: repo,
                           branch: branch, issue_number: issue_number, summary: summary, token: token)
        expect(result[:success]).to be(false)
        expect(result[:reason]).to eq('git push failed')
      end

      it 'does not call open_pr' do
        host.ship(checkout_path: checkout_path, owner: owner, repo: repo,
                  branch: branch, issue_number: issue_number, summary: summary, token: token)
        expect(host).not_to have_received(:open_pr)
      end
    end

    context 'when a StandardError is raised' do
      before do
        allow(host).to receive(:commit_and_push).and_raise(StandardError, 'unexpected explosion')
      end

      it 'returns success: false' do
        result = host.ship(checkout_path: checkout_path, owner: owner, repo: repo,
                           branch: branch, issue_number: issue_number, summary: summary, token: token)
        expect(result[:success]).to be(false)
      end

      it 'returns the exception message as reason' do
        result = host.ship(checkout_path: checkout_path, owner: owner, repo: repo,
                           branch: branch, issue_number: issue_number, summary: summary, token: token)
        expect(result[:reason]).to eq('unexpected explosion')
      end
    end
  end
end

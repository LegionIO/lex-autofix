# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/autofix/runners/fix'

RSpec.describe Legion::Extensions::Autofix::Runners::Fix do
  subject(:host) { Object.new.extend(described_class) }

  let(:repo_url) { 'https://github.com/LegionIO/lex-foo' }
  let(:branch)   { 'autofix/runtime-error' }
  let(:checkout_path) { '/tmp/autofix_test/checkout_abc123' }

  let(:error_details) do
    {
      exception_class: 'RuntimeError',
      message:         'boom',
      caller_file:     'lib/lex/foo/runner.rb',
      backtrace:       ['lib/lex/foo/runner.rb:42:in `run`', 'lib/lex/foo/actor.rb:10:in `call`']
    }
  end

  let(:edits) do
    [{ 'file' => 'lib/lex/foo/runner.rb', 'old' => 'raise RuntimeError', 'new' => '# fixed' }]
  end

  let(:llm_response) { { edits: edits } }

  let(:tc) do
    instance_double(Legion::Extensions::Autofix::Helpers::TempCheckout,
                    clone:       { success: true, path: checkout_path },
                    read_files:  { 'lib/lex/foo/runner.rb' => 'raise RuntimeError' },
                    apply_edits: { success: true },
                    cleanup:     { success: true })
  end

  before do
    stub_const('Legion::LLM', Module.new { def self.structured(**); end })
    allow(Legion::LLM).to receive(:structured).and_return(llm_response)
    allow(Legion::Extensions::Autofix::Helpers::TempCheckout).to receive(:new).and_return(tc)
  end

  describe '#attempt_fix' do
    context 'when clone fails' do
      before do
        allow(tc).to receive(:clone).and_return({ success: false, reason: 'git clone failed' })
      end

      it 'returns the clone failure result' do
        result = host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details)
        expect(result[:success]).to be(false)
        expect(result[:reason]).to eq('git clone failed')
      end

      it 'does not call LLM' do
        host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details)
        expect(Legion::LLM).not_to have_received(:structured)
      end
    end

    context 'when apply_edits returns stale context failure' do
      before do
        allow(tc).to receive(:apply_edits).and_return(
          { success: false, reason: 'old string not found in lib/lex/foo/runner.rb' }
        )
      end

      it 'returns success: false' do
        result = host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details)
        expect(result[:success]).to be(false)
      end

      it 'includes the apply_edits reason' do
        result = host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details)
        expect(result[:reason]).to eq('old string not found in lib/lex/foo/runner.rb')
      end

      it 'cleans up the checkout' do
        host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details)
        expect(tc).to have_received(:cleanup).with(checkout_path)
      end
    end

    context 'when tests pass and lint passes on first attempt' do
      before do
        allow(host).to receive(:run_tests).and_return({ success: true, output: '' })
        allow(host).to receive(:run_lint).and_return({ success: true, output: '' })
      end

      it 'returns success: true' do
        result = host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details)
        expect(result[:success]).to be(true)
      end

      it 'returns the checkout_path' do
        result = host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details)
        expect(result[:checkout_path]).to eq(checkout_path)
      end

      it 'calls LLM once' do
        host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details)
        expect(Legion::LLM).to have_received(:structured).once
      end

      it 'passes checkout_dir to TempCheckout when provided' do
        host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details,
                         checkout_dir: '/tmp/custom')
        expect(Legion::Extensions::Autofix::Helpers::TempCheckout).to have_received(:new)
          .with(base_dir: '/tmp/custom')
      end

      it 'instantiates TempCheckout with no args when checkout_dir is nil' do
        host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details)
        expect(Legion::Extensions::Autofix::Helpers::TempCheckout).to have_received(:new).with(no_args)
      end
    end

    context 'when tests fail on all retries' do
      let(:max_retries) { 2 }

      before do
        allow(host).to receive(:run_tests).and_return({ success: false, output: 'FAILED: 3 examples' })
        allow(host).to receive(:run_lint)
        allow(host).to receive(:system).and_return(true)
      end

      it 'returns success: false' do
        result = host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details,
                                  max_retries: max_retries)
        expect(result[:success]).to be(false)
      end

      it 'includes the max retries in the reason' do
        result = host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details,
                                  max_retries: max_retries)
        expect(result[:reason]).to eq("fix failed after max retries (#{max_retries})")
      end

      it 'calls LLM once per retry attempt' do
        host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details,
                         max_retries: max_retries)
        expect(Legion::LLM).to have_received(:structured).exactly(max_retries).times
      end

      it 'uses fix prompt on first attempt and fix_retry on subsequent attempts' do
        prompts = []
        allow(Legion::LLM).to receive(:structured) do |args|
          prompts << args[:messages].first[:content]
          llm_response
        end
        host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details,
                         max_retries: max_retries)
        expect(prompts.first).not_to include('Previous Fix Attempt Failed')
        expect(prompts.last).to include('Previous Fix Attempt Failed')
      end

      it 'cleans up after exhausting retries' do
        host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details,
                         max_retries: max_retries)
        expect(tc).to have_received(:cleanup).with(checkout_path)
      end
    end

    context 'when a StandardError is raised' do
      let(:logger) { double('logger', log_exception: nil) }

      before do
        allow(tc).to receive(:clone).and_raise(StandardError, 'unexpected explosion')
        log_double = logger
        host.define_singleton_method(:log) { log_double }
      end

      it 'returns success: false' do
        result = host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details)
        expect(result[:success]).to be(false)
      end

      it 'returns the exception message as reason' do
        result = host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details)
        expect(result[:reason]).to eq('unexpected explosion')
      end
    end
  end

  describe '#run_tests' do
    before do
      allow(Dir).to receive(:chdir).with(checkout_path).and_yield
      allow(host).to receive(:system).and_return(true)
      allow(host).to receive(:`).and_return("3 examples, 0 failures\n")
    end

    it 'returns a hash with success and output keys' do
      result = host.run_tests(checkout_path: checkout_path)
      expect(result).to have_key(:success)
      expect(result).to have_key(:output)
    end

    it 'runs bundle install' do
      host.run_tests(checkout_path: checkout_path)
      expect(host).to have_received(:system).with('bundle', 'install', '--quiet')
    end

    it 'captures rspec output' do
      result = host.run_tests(checkout_path: checkout_path)
      expect(result[:output]).to eq("3 examples, 0 failures\n")
    end
  end

  describe '#run_lint' do
    before do
      allow(Dir).to receive(:chdir).with(checkout_path).and_yield
      allow(host).to receive(:system).and_return(true)
      allow(host).to receive(:`).and_return("no offenses detected\n")
    end

    it 'returns a hash with success and output keys' do
      result = host.run_lint(checkout_path: checkout_path)
      expect(result).to have_key(:success)
      expect(result).to have_key(:output)
    end

    it 'runs rubocop auto-correct first' do
      host.run_lint(checkout_path: checkout_path)
      expect(host).to have_received(:system).with('bundle', 'exec', 'rubocop', '-A')
    end

    it 'captures rubocop output' do
      result = host.run_lint(checkout_path: checkout_path)
      expect(result[:output]).to eq("no offenses detected\n")
    end
  end

  describe 'file path extraction' do
    before do
      allow(host).to receive(:run_tests).and_return({ success: true, output: '' })
      allow(host).to receive(:run_lint).and_return({ success: true, output: '' })
    end

    it 'deduplicates overlapping lib and backtrace paths' do
      allow(tc).to receive(:read_files) do |args|
        paths = args[:file_paths]
        expect(paths).to include('lib/lex/foo/runner.rb')
        expect(paths).to include('lib/lex/foo/actor.rb')
        expect(paths.count('lib/lex/foo/runner.rb')).to eq(1)
        {}
      end
      host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details)
    end

    it 'includes corresponding spec files' do
      allow(tc).to receive(:read_files) do |args|
        paths = args[:file_paths]
        expect(paths).to include('spec/lex/foo/runner_spec.rb')
        {}
      end
      host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details)
    end

    context 'when gem_path is provided' do
      let(:error_details_with_gem_path) do
        {
          exception_class: 'RuntimeError',
          message:         'boom',
          gem_path:        '/var/lib/gems/lex-foo-1.0.0',
          caller_file:     '/var/lib/gems/lex-foo-1.0.0/lib/lex/foo/runner.rb',
          backtrace:       ['/var/lib/gems/lex-foo-1.0.0/lib/lex/foo/actor.rb:10:in `call`']
        }
      end

      it 'strips the gem_path prefix from caller_file' do
        allow(tc).to receive(:read_files) do |args|
          paths = args[:file_paths]
          expect(paths).to include('lib/lex/foo/runner.rb')
          expect(paths).not_to include('/var/lib/gems/lex-foo-1.0.0/lib/lex/foo/runner.rb')
          {}
        end
        host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details_with_gem_path)
      end

      it 'strips the gem_path prefix from backtrace paths' do
        allow(tc).to receive(:read_files) do |args|
          paths = args[:file_paths]
          expect(paths).to include('lib/lex/foo/actor.rb')
          expect(paths).not_to include('/var/lib/gems/lex-foo-1.0.0/lib/lex/foo/actor.rb')
          {}
        end
        host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details_with_gem_path)
      end
    end

    context 'when gem_path is absent' do
      it 'returns paths unchanged' do
        allow(tc).to receive(:read_files) do |args|
          paths = args[:file_paths]
          expect(paths).to include('lib/lex/foo/runner.rb')
          {}
        end
        host.attempt_fix(repo_url: repo_url, branch: branch, error_details: error_details)
      end
    end
  end

  describe '#strip_gem_prefix' do
    it 'removes the gem_base prefix from a path' do
      result = host.send(:strip_gem_prefix, '/gems/lex-foo/lib/foo.rb', '/gems/lex-foo')
      expect(result).to eq('lib/foo.rb')
    end

    it 'returns the path unchanged when gem_base is empty' do
      result = host.send(:strip_gem_prefix, 'lib/foo.rb', '')
      expect(result).to eq('lib/foo.rb')
    end

    it 'returns the path unchanged when gem_base does not match' do
      result = host.send(:strip_gem_prefix, '/other/path/lib/foo.rb', '/gems/lex-foo')
      expect(result).to eq('/other/path/lib/foo.rb')
    end
  end
end

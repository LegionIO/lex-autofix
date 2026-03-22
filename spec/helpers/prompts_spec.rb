# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/autofix/helpers/prompts'

RSpec.describe Legion::Extensions::Autofix::Helpers::Prompts do
  let(:events) do
    [
      { lex: 'lex-foo', exception_class: 'RuntimeError', message: 'boom', backtrace: ['foo.rb:1'] },
      { lex: 'lex-foo', exception_class: 'RuntimeError', message: 'boom again', backtrace: ['foo.rb:2'] }
    ]
  end

  let(:error_details) do
    {
      exception_class: 'ArgumentError',
      message:         'wrong number of arguments',
      backtrace:       ['lib/foo.rb:10:in `bar`', 'lib/foo.rb:20:in `baz`']
    }
  end

  let(:files) do
    { 'lib/foo.rb' => "def bar(x)\n  x.upcase\nend" }
  end

  describe '.triage' do
    subject(:prompt) { described_class.triage(events) }

    it 'returns a String' do
      expect(prompt).to be_a(String)
    end

    it 'includes the word "clusters" in the prompt' do
      expect(prompt).to include('clusters')
    end

    it 'includes the serialized event data' do
      expect(prompt).to include('lex-foo')
      expect(prompt).to include('RuntimeError')
    end

    it 'pretty-prints the events as JSON' do
      expect(prompt).to include('"exception_class"')
    end
  end

  describe '.triage_schema' do
    subject(:schema) { described_class.triage_schema }

    it 'returns a Hash' do
      expect(schema).to be_a(Hash)
    end

    it 'has type object' do
      expect(schema[:type]).to eq('object')
    end

    it 'requires clusters' do
      expect(schema[:required]).to include('clusters')
    end

    it 'defines clusters as an array' do
      expect(schema.dig(:properties, :clusters, :type)).to eq('array')
    end

    it 'cluster items require id, summary, actionable, and events' do
      required = schema.dig(:properties, :clusters, :items, :required)
      expect(required).to include('id', 'summary', 'actionable', 'events')
    end

    it 'cluster items define all six expected properties' do
      props = schema.dig(:properties, :clusters, :items, :properties)
      expect(props.keys).to include(:id, :summary, :actionable, :reason, :events, :suggested_repo)
    end
  end

  describe '.fix' do
    subject(:prompt) { described_class.fix(error_details: error_details, files: files) }

    it 'returns a String' do
      expect(prompt).to be_a(String)
    end

    it 'includes the exception class' do
      expect(prompt).to include('ArgumentError')
    end

    it 'includes the error message' do
      expect(prompt).to include('wrong number of arguments')
    end

    it 'includes the file path' do
      expect(prompt).to include('lib/foo.rb')
    end

    it 'includes the file content' do
      expect(prompt).to include('def bar(x)')
    end

    it 'includes backtrace lines' do
      expect(prompt).to include('lib/foo.rb:10')
    end
  end

  describe '.fix_retry' do
    subject(:prompt) do
      described_class.fix_retry(error_details: error_details, files: files, test_output: test_output)
    end

    let(:test_output) { "1 example, 1 failure\nExpected 'hello' but got nil" }

    it 'returns a String' do
      expect(prompt).to be_a(String)
    end

    it 'includes the test output' do
      expect(prompt).to include('1 example, 1 failure')
      expect(prompt).to include("Expected 'hello' but got nil")
    end

    it 'still includes the exception class from the base fix prompt' do
      expect(prompt).to include('ArgumentError')
    end

    it 'still includes the file content from the base fix prompt' do
      expect(prompt).to include('def bar(x)')
    end

    it 'mentions that the previous fix attempt failed' do
      expect(prompt).to include('Previous Fix Attempt Failed')
    end
  end

  describe '.fix_schema' do
    subject(:schema) { described_class.fix_schema }

    it 'returns a Hash' do
      expect(schema).to be_a(Hash)
    end

    it 'has type object' do
      expect(schema[:type]).to eq('object')
    end

    it 'requires edits' do
      expect(schema[:required]).to include('edits')
    end

    it 'defines edits as an array' do
      expect(schema.dig(:properties, :edits, :type)).to eq('array')
    end

    it 'edit items require file, old, and new' do
      required = schema.dig(:properties, :edits, :items, :required)
      expect(required).to include('file', 'old', 'new')
    end

    it 'edit items define all three expected properties' do
      props = schema.dig(:properties, :edits, :items, :properties)
      expect(props.keys).to include(:file, :old, :new)
    end
  end
end

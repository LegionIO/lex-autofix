# frozen_string_literal: true

require 'spec_helper'

unless defined?(Legion::Transport::Queue)
  module Legion
    module Transport
      class Queue
        def queue_name; end
        def queue_options = {}
      end
    end
  end
end

unless defined?(Legion::Extensions::Transport)
  module Legion
    module Extensions
      module Transport; end
    end
  end
end

unless defined?(Legion::Extensions::Autofix::Transport)
  module Legion
    module Extensions
      module Autofix
        module Transport
          module Queues; end
        end
      end
    end
  end
end

require 'legion/extensions/autofix/transport'
require 'legion/extensions/autofix/transport/queues/ingest'

RSpec.describe Legion::Extensions::Autofix::Transport do
  describe '.additional_e_to_q' do
    let(:bindings) { described_class.additional_e_to_q }

    it 'returns 3 bindings for warn, error, fatal' do
      expect(bindings.size).to eq(3)
    end

    it 'binds from legion.logging exchange' do
      bindings.each { |b| expect(b[:from]).to eq('legion.logging') }
    end

    it 'binds to autofix.ingest queue' do
      bindings.each { |b| expect(b[:to]).to eq('autofix.ingest') }
    end

    it 'uses exception routing key prefix' do
      keys = bindings.map { |b| b[:routing_key] }
      expect(keys).to contain_exactly(
        'legion.logging.exception.warn.#',
        'legion.logging.exception.error.#',
        'legion.logging.exception.fatal.#'
      )
    end
  end
end

RSpec.describe Legion::Extensions::Autofix::Transport::Queues::Ingest do
  subject(:ingest) { described_class.new }

  describe '#queue_name' do
    it 'returns autofix.ingest' do
      expect(ingest.queue_name).to eq('autofix.ingest')
    end
  end

  describe '#queue_options' do
    it 'returns durable true' do
      expect(ingest.queue_options[:durable]).to be(true)
    end

    it 'returns auto_delete false' do
      expect(ingest.queue_options[:auto_delete]).to be(false)
    end
  end
end

# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/autofix/helpers/batch_buffer'

RSpec.describe Legion::Extensions::Autofix::Helpers::BatchBuffer do
  subject(:buffer) { described_class.new(window_seconds: 300, count_threshold: 3) }

  describe '#initialize' do
    it 'starts empty' do
      expect(buffer.size).to eq(0)
    end

    it 'starts with empty groups' do
      expect(buffer.groups).to eq({})
    end
  end

  describe '#add' do
    it 'groups events by lex:exception_class key' do
      buffer.add({ lex: 'mylex', exception_class: 'RuntimeError', msg: 'oops' })
      buffer.add({ lex: 'mylex', exception_class: 'RuntimeError', msg: 'again' })
      expect(buffer.groups['mylex:RuntimeError'].length).to eq(2)
    end

    it 'separates events into distinct groups by key' do
      buffer.add({ lex: 'mylex', exception_class: 'RuntimeError' })
      buffer.add({ lex: 'mylex', exception_class: 'ArgumentError' })
      expect(buffer.groups.keys).to contain_exactly('mylex:RuntimeError', 'mylex:ArgumentError')
    end

    it 'defaults lex to "core" when nil' do
      buffer.add({ lex: nil, exception_class: 'RuntimeError' })
      expect(buffer.groups.keys).to include('core:RuntimeError')
    end

    it 'defaults exception_class to "unknown" when nil' do
      buffer.add({ lex: 'mylex', exception_class: nil })
      expect(buffer.groups.keys).to include('mylex:unknown')
    end

    it 'defaults both lex and exception_class when both nil' do
      buffer.add({ lex: nil, exception_class: nil })
      expect(buffer.groups.keys).to include('core:unknown')
    end

    it 'defaults lex and exception_class when keys are absent' do
      buffer.add({})
      expect(buffer.groups.keys).to include('core:unknown')
    end

    it 'uses error_fingerprint as the group key when present' do
      buffer.add({ error_fingerprint: 'abc123', lex: 'mylex', exception_class: 'RuntimeError' })
      buffer.add({ error_fingerprint: 'abc123', lex: 'mylex', exception_class: 'RuntimeError' })
      expect(buffer.groups['abc123'].length).to eq(2)
    end

    it 'falls back to lex:exception_class when error_fingerprint is absent' do
      buffer.add({ lex: 'mylex', exception_class: 'RuntimeError' })
      expect(buffer.groups.keys).to include('mylex:RuntimeError')
    end

    it 'increments total size' do
      buffer.add({ lex: 'a', exception_class: 'E' })
      buffer.add({ lex: 'b', exception_class: 'E' })
      expect(buffer.size).to eq(2)
    end
  end

  describe '#flush_ready?' do
    it 'returns false when buffer is empty' do
      expect(buffer.flush_ready?).to be(false)
    end

    it 'returns false when count is below threshold and window has not elapsed' do
      buffer.add({ lex: 'mylex', exception_class: 'RuntimeError' })
      buffer.add({ lex: 'mylex', exception_class: 'RuntimeError' })
      expect(buffer.flush_ready?).to be(false)
    end

    it 'returns true when a group reaches the count threshold' do
      buffer.add({ lex: 'mylex', exception_class: 'RuntimeError' })
      buffer.add({ lex: 'mylex', exception_class: 'RuntimeError' })
      buffer.add({ lex: 'mylex', exception_class: 'RuntimeError' })
      expect(buffer.flush_ready?).to be(true)
    end

    it 'threshold check is per-group, not total' do
      # 2 events in each of 2 groups = 4 total, but no group hits threshold of 3
      buffer.add({ lex: 'a', exception_class: 'E' })
      buffer.add({ lex: 'a', exception_class: 'E' })
      buffer.add({ lex: 'b', exception_class: 'E' })
      buffer.add({ lex: 'b', exception_class: 'E' })
      expect(buffer.flush_ready?).to be(false)
    end

    it 'returns true when the time window has elapsed' do
      # Stub clock before add so @first_event_time is set from the stub too
      base = 1_000_000.0
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(base, base + 301)
      buffer.add({ lex: 'mylex', exception_class: 'RuntimeError' })
      expect(buffer.flush_ready?).to be(true)
    end

    it 'returns false when time window has not elapsed and count is below threshold' do
      base = 1_000_000.0
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(base, base + 10)
      buffer.add({ lex: 'mylex', exception_class: 'RuntimeError' })
      expect(buffer.flush_ready?).to be(false)
    end
  end

  describe '#flush!' do
    it 'returns all events as a flat array' do
      buffer.add({ lex: 'a', exception_class: 'E', n: 1 })
      buffer.add({ lex: 'a', exception_class: 'E', n: 2 })
      buffer.add({ lex: 'b', exception_class: 'F', n: 3 })
      result = buffer.flush!
      expect(result.length).to eq(3)
      expect(result.map { |e| e[:n] }).to contain_exactly(1, 2, 3)
    end

    it 'clears the buffer after flush' do
      buffer.add({ lex: 'a', exception_class: 'E' })
      buffer.flush!
      expect(buffer.size).to eq(0)
      expect(buffer.groups).to eq({})
    end

    it 'resets first_event_time after flush' do
      buffer.add({ lex: 'a', exception_class: 'E' })
      buffer.flush!
      # After flush, stub clock for the new add + flush_ready? check
      base = 2_000_000.0
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(base, base + 10)
      buffer.add({ lex: 'a', exception_class: 'E' })
      expect(buffer.flush_ready?).to be(false)
    end

    it 'returns an empty array when buffer is empty' do
      expect(buffer.flush!).to eq([])
    end
  end

  describe '#size' do
    it 'returns 0 for an empty buffer' do
      expect(buffer.size).to eq(0)
    end

    it 'counts events across multiple groups' do
      buffer.add({ lex: 'a', exception_class: 'E' })
      buffer.add({ lex: 'a', exception_class: 'E' })
      buffer.add({ lex: 'b', exception_class: 'F' })
      expect(buffer.size).to eq(3)
    end
  end
end

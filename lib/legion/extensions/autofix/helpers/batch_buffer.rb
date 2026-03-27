# frozen_string_literal: true

module Legion
  module Extensions
    module Autofix
      module Helpers
        # Thread-safe in-memory buffer that groups error events by lex:exception_class key.
        # Flush is triggered when a group reaches count_threshold OR the time window elapses.
        class BatchBuffer
          DEFAULT_WINDOW_SECONDS = 300
          DEFAULT_COUNT_THRESHOLD = 3

          attr_reader :groups

          def initialize(window_seconds: DEFAULT_WINDOW_SECONDS, count_threshold: DEFAULT_COUNT_THRESHOLD)
            @window_seconds  = window_seconds
            @count_threshold = count_threshold
            @groups          = {}
            @first_event_time = nil
            @mutex = Mutex.new
          end

          def add(event)
            @mutex.synchronize do
              key = build_key(event)
              @groups[key] ||= []
              @groups[key] << event
              @first_event_time ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
            end
          end

          def flush_ready?
            @mutex.synchronize do
              return false if @groups.empty?

              return true if @groups.any? { |_, events| events.length >= @count_threshold }

              elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @first_event_time
              elapsed >= @window_seconds
            end
          end

          def flush!
            @mutex.synchronize do
              all_events = @groups.values.flatten
              @groups = {}
              @first_event_time = nil
              all_events
            end
          end

          def size
            @mutex.synchronize { @groups.values.sum(&:length) }
          end

          private

          def build_key(event)
            return event[:error_fingerprint] if event[:error_fingerprint]

            lex             = event[:lex] || 'core'
            exception_class = event[:exception_class] || 'unknown'
            "#{lex}:#{exception_class}"
          end
        end
      end
    end
  end
end

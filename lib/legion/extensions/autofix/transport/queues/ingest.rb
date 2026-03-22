# frozen_string_literal: true

module Legion
  module Extensions
    module Autofix
      module Transport
        module Queues
          class Ingest < Legion::Transport::Queue
            def queue_name = 'autofix.ingest'
            def queue_options = { durable: true, auto_delete: false }
          end
        end
      end
    end
  end
end

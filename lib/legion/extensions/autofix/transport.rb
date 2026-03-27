# frozen_string_literal: true

module Legion
  module Extensions
    module Autofix
      module Transport
        extend Legion::Extensions::Transport if defined?(Legion::Extensions::Transport)

        def self.additional_e_to_q
          %w[warn error fatal].map do |level|
            { from: 'legion.logging', to: 'autofix.ingest', routing_key: "legion.logging.exception.#{level}.#" }
          end
        end
      end
    end
  end
end

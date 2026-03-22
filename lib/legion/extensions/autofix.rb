# frozen_string_literal: true

require_relative 'autofix/version'

module Legion
  module Extensions
    module Autofix
      extend Legion::Extensions::Core if defined?(Legion::Extensions::Core)

      def self.llm_required?
        true
      end
    end
  end
end

# Require components when framework is available
if defined?(Legion::Extensions::Core)
  require_relative 'autofix/helpers/batch_buffer'
  require_relative 'autofix/helpers/prompts'
  require_relative 'autofix/helpers/temp_checkout'
  require_relative 'autofix/helpers/client'
  require_relative 'autofix/runners/triage'
  require_relative 'autofix/runners/diagnose'
  require_relative 'autofix/runners/fix'
  require_relative 'autofix/runners/ship'
  require_relative 'autofix/runners/pipeline'
  require_relative 'autofix/client'
  require_relative 'autofix/transport' if defined?(Legion::Extensions::Transport)
  require_relative 'autofix/actors/log_consumer' if defined?(Legion::Extensions::Actors::Subscription)
end

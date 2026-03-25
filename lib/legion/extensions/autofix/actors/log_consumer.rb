# frozen_string_literal: true

module Legion
  module Extensions
    module Autofix
      module Actor
        class LogConsumer < Legion::Extensions::Actors::Subscription
          def runner_class = Legion::Extensions::Autofix::Runners::Pipeline
          def runner_function = 'handle_log_event'
          def check_subtask? = false
          def generate_task? = false

          def enabled?
            !!(defined?(Legion::LLM) && Legion::LLM.respond_to?(:started?) && Legion::LLM.started?)
          end
        end
      end
    end
  end
end

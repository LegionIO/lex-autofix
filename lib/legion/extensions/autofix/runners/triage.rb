# frozen_string_literal: true

require_relative '../helpers/prompts'

module Legion
  module Extensions
    module Autofix
      module Runners
        module Triage # rubocop:disable Legion/Extension/RunnerIncludeHelpers
          def batch_triage(events:, **)
            return { success: false, reason: 'no events to triage' } if events.empty?

            prompt = Helpers::Prompts.triage(events)
            schema = Helpers::Prompts.triage_schema

            result = Legion::LLM.structured(
              messages: [{ role: 'user', content: prompt }],
              schema:   schema,
              caller:   { extension: 'lex-autofix', operation: 'triage' }
            )

            clusters = result[:clusters] || []
            actionable, non_actionable = clusters.partition { |c| c[:actionable] }

            { success: true, clusters: clusters, actionable: actionable, non_actionable: non_actionable }
          rescue StandardError => e
            { success: false, reason: e.message }
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

require 'json'

module Legion
  module Extensions
    module Autofix
      module Helpers
        module Prompts
          module_function

          def triage(events)
            serialized = ::JSON.pretty_generate(events)
            <<~PROMPT
              You are an expert Ruby engineer analyzing error telemetry from a running system.

              Below is a JSON array of error events captured from one or more LegionIO extensions.
              Your job is to group these errors into clusters based on their type, origin, and likely root cause.

              For each cluster, decide:
              - Whether it is actionable (can be fixed by editing source code)
              - A brief summary of what is going wrong
              - Which repository (gem) is the likely owner of the fix
              - The list of event indices belonging to this cluster

              Return ONLY valid JSON matching the required schema. Do not include any explanation outside the JSON.

              Events:
              #{serialized}
            PROMPT
          end

          def triage_schema
            {
              type:       'object',
              properties: {
                clusters: {
                  type:  'array',
                  items: {
                    type:       'object',
                    properties: {
                      id:             { type: 'string' },
                      summary:        { type: 'string' },
                      actionable:     { type: 'boolean' },
                      reason:         { type: 'string' },
                      events:         { type: 'array', items: { type: 'integer' } },
                      suggested_repo: { type: 'string' }
                    },
                    required:   %w[id summary actionable events]
                  }
                }
              },
              required:   %w[clusters]
            }
          end

          def fix(error_details:, files:)
            file_section = files.map do |path, content|
              "### #{path}\n```ruby\n#{content}\n```"
            end.join("\n\n")

            <<~PROMPT
              You are an expert Ruby engineer. Your task is to produce a minimal code fix for the error described below.

              ## Error Details

              Exception class: #{error_details[:exception_class]}
              Message: #{error_details[:message]}
              Backtrace:
              #{Array(error_details[:backtrace]).first(10).map { |l| "  #{l}" }.join("\n")}

              ## Source Files

              #{file_section}

              ## Instructions

              Analyze the error and the source files above. Produce the smallest set of edits that fixes the issue.
              Each edit must specify the exact old string to replace and the new string to substitute.
              Return ONLY valid JSON matching the required schema. Do not include explanation outside the JSON.
            PROMPT
          end

          def fix_retry(error_details:, files:, test_output:)
            base = fix(error_details: error_details, files: files)
            <<~PROMPT
              #{base.chomp}

              ## Previous Fix Attempt Failed

              The prior fix was applied but tests still failed. Here is the test output:

              ```
              #{test_output}
              ```

              Review the test failures above and produce a revised set of edits.
              Return ONLY valid JSON matching the required schema. Do not include explanation outside the JSON.
            PROMPT
          end

          def fix_schema
            {
              type:       'object',
              properties: {
                edits: {
                  type:  'array',
                  items: {
                    type:       'object',
                    properties: {
                      file: { type: 'string' },
                      old:  { type: 'string' },
                      new:  { type: 'string' }
                    },
                    required:   %w[file old new]
                  }
                }
              },
              required:   %w[edits]
            }
          end
        end
      end
    end
  end
end

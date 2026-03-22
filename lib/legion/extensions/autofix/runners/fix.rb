# frozen_string_literal: true

require_relative '../helpers/prompts'
require_relative '../helpers/temp_checkout'

module Legion
  module Extensions
    module Autofix
      module Runners
        module Fix
          def attempt_fix(repo_url:, branch:, error_details:, max_retries: 3, checkout_dir: nil)
            tc_opts = checkout_dir ? { base_dir: checkout_dir } : {}
            tc = Helpers::TempCheckout.new(**tc_opts)

            clone_result = tc.clone(repo_url: repo_url, branch: branch)
            return clone_result unless clone_result[:success]

            checkout_path = clone_result[:path]
            file_paths = extract_file_paths(error_details)
            files = tc.read_files(checkout_path: checkout_path, file_paths: file_paths)

            schema = Helpers::Prompts.fix_schema
            test_output = nil

            max_retries.times do |attempt|
              messages = build_messages(attempt: attempt, error_details: error_details,
                                        files: files, test_output: test_output)

              llm_result = Legion::LLM.structured(messages: messages, schema: schema)
              edits = llm_result[:edits] || []

              apply_result = tc.apply_edits(checkout_path: checkout_path, edits: edits)
              unless apply_result[:success]
                tc.cleanup(checkout_path)
                return { success: false, reason: apply_result[:reason] }
              end

              test_result = run_tests(checkout_path: checkout_path)
              if test_result[:success]
                lint_result = run_lint(checkout_path: checkout_path)
                return { success: true, checkout_path: checkout_path } if lint_result[:success]

                test_output = lint_result[:output]
              else
                test_output = test_result[:output]
              end

              system('git', '-C', checkout_path, 'checkout', '.')
            end

            tc.cleanup(checkout_path)
            { success: false, reason: "fix failed after max retries (#{max_retries})" }
          rescue StandardError => e
            { success: false, reason: e.message }
          end

          def run_tests(checkout_path:)
            Dir.chdir(checkout_path) do
              system('bundle', 'install', '--quiet')
              output = `bundle exec rspec 2>&1`
              { success: $CHILD_STATUS&.success?, output: output }
            end
          end

          def run_lint(checkout_path:)
            Dir.chdir(checkout_path) do
              system('bundle', 'exec', 'rubocop', '-A')
              output = `bundle exec rubocop 2>&1`
              { success: $CHILD_STATUS&.success?, output: output }
            end
          end

          private

          def extract_file_paths(error_details)
            paths = []
            paths << error_details[:caller_file] if error_details[:caller_file]

            Array(error_details[:backtrace]).each do |line|
              file = line.to_s.split(':').first
              paths << file if file && !file.empty?
            end

            paths = paths.uniq
            spec_paths = paths.map { |p| p.sub('lib/', 'spec/').sub(/\.rb$/, '_spec.rb') }
            (paths + spec_paths).uniq
          end

          def build_messages(attempt:, error_details:, files:, test_output:)
            prompt = if attempt.zero?
                       Helpers::Prompts.fix(error_details: error_details, files: files)
                     else
                       Helpers::Prompts.fix_retry(error_details: error_details, files: files,
                                                  test_output: test_output.to_s)
                     end
            [{ role: 'user', content: prompt }]
          end
        end
      end
    end
  end
end

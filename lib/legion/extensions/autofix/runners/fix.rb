# frozen_string_literal: true

require_relative '../helpers/prompts'
require_relative '../helpers/temp_checkout'

module Legion
  module Extensions
    module Autofix
      module Runners
        module Fix
          def attempt_fix(repo_url: nil, branch: nil, error_details: nil, issue_number: nil, # rubocop:disable Metrics/ParameterLists
                          org: nil, repo: nil, summary: nil, max_retries: 3, checkout_dir: nil, **)
            repo_url ||= "https://github.com/#{org}/#{repo}.git" if org && repo
            branch ||= "autofix/#{issue_number}-#{slug(summary || 'fix')}" if issue_number
            error_details ||= {}

            tc_opts = checkout_dir ? { base_dir: checkout_dir } : {}
            tc = Helpers::TempCheckout.new(**tc_opts)

            clone_result = tc.clone(repo_url: repo_url, branch: branch)
            unless clone_result[:success]
              return clone_result.merge(issue_number: issue_number, org: org, repo: repo,
                                        branch: branch, summary: summary)
            end

            checkout_path = clone_result[:path]
            file_paths = extract_file_paths(error_details)
            files = tc.read_files(checkout_path: checkout_path, file_paths: file_paths)

            schema = Helpers::Prompts.fix_schema
            test_output = nil

            max_retries.times do |attempt|
              messages = build_messages(attempt: attempt, error_details: error_details,
                                        files: files, test_output: test_output)

              llm_result = Legion::LLM.structured(messages: messages, schema: schema,
                                                  caller: { extension: 'lex-autofix', operation: 'fix' },
                                                  intent: { capability: :reasoning })
              edits = llm_result[:edits] || []

              apply_result = tc.apply_edits(checkout_path: checkout_path, edits: edits)
              unless apply_result[:success]
                tc.cleanup(checkout_path)
                return { success: false, reason: apply_result[:reason] }
              end

              test_result = run_tests(checkout_path: checkout_path)
              if test_result[:success]
                lint_result = run_lint(checkout_path: checkout_path)
                if lint_result[:success]
                  return { success: true, checkout_path: checkout_path,
                           issue_number: issue_number, org: org, repo: repo,
                           branch: branch, summary: summary }
                end

                test_output = lint_result[:output]
              else
                test_output = test_result[:output]
              end

              system('git', '-C', checkout_path, 'checkout', '.')
            end

            tc.cleanup(checkout_path)
            { success: false, reason: "fix failed after max retries (#{max_retries})" }
          rescue StandardError => e
            log.log_exception(e, context: 'autofix: attempt_fix failed')
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
            gem_base = error_details[:gem_path].to_s
            paths = []
            paths << strip_gem_prefix(error_details[:caller_file].to_s, gem_base)

            Array(error_details[:backtrace]).each do |line|
              file = line.to_s.split(':').first
              next if file.nil? || file.empty?

              paths << strip_gem_prefix(file, gem_base)
            end

            paths = paths.uniq.reject(&:empty?)
            spec_paths = paths.map { |p| p.sub('lib/', 'spec/').sub(/\.rb$/, '_spec.rb') }
            (paths + spec_paths).uniq
          end

          def strip_gem_prefix(path, gem_base)
            return path if gem_base.empty?

            path.delete_prefix("#{gem_base}/")
          end

          def slug(text)
            text.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-+|-+$/, '')[0, 40]
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

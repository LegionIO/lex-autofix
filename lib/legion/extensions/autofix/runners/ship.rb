# frozen_string_literal: true

require_relative '../helpers/temp_checkout'

module Legion
  module Extensions
    module Autofix
      module Runners
        module Ship
          def commit_and_push(checkout_path:, branch:, message:)
            Dir.chdir(checkout_path) do
              return { success: false, reason: 'git add failed' } unless system('git', 'add', '-A')
              return { success: false, reason: 'git commit failed' } unless system('git', 'commit', '-m', message)
              return { success: false, reason: 'git push failed' } unless system('git', 'push', '-u', 'origin', branch)
            end

            { success: true }
          end

          def open_pr(owner:, repo:, branch:, title:, body:, token:) # rubocop:disable Metrics/ParameterLists
            client = Legion::Extensions::Github::Client.new(token: token)
            result = client.create_pull_request(
              owner: owner,
              repo:  repo,
              title: title,
              head:  branch,
              base:  'main',
              body:  body
            )
            pr = result[:result] || result
            { success: true, pr_number: pr[:number], url: pr[:html_url] }
          rescue StandardError => e
            { success: false, reason: e.message }
          end

          def ship(checkout_path:, branch:, issue_number:, summary:, owner: nil, repo: nil, # rubocop:disable Metrics/ParameterLists
                   token: nil, org: nil, checkout_dir: nil, **)
            owner ||= org
            token ||= resolve_token
            commit_result = commit_and_push(
              checkout_path: checkout_path,
              branch:        branch,
              message:       "fix: #{summary}"
            )
            return commit_result unless commit_result[:success]

            pr_result = open_pr(
              owner:  owner,
              repo:   repo,
              branch: branch,
              title:  "fix: #{summary}",
              body:   "Closes ##{issue_number}\n\nAutomated fix by lex-autofix.",
              token:  token
            )

            tc_opts = checkout_dir ? { base_dir: checkout_dir } : {}
            Helpers::TempCheckout.new(**tc_opts).cleanup(checkout_path)

            pr_result
          rescue StandardError => e
            { success: false, reason: e.message }
          end
        end
      end
    end
  end
end

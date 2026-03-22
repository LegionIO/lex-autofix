# frozen_string_literal: true

module Legion
  module Extensions
    module Autofix
      module Runners
        module Diagnose
          def check_github(cluster:, events:, token:, org: 'LegionIO')
            repo = cluster[:suggested_repo]
            exception_class = events.first[:exception_class] || 'unknown'
            client = Legion::Extensions::Github::Client.new(token: token)
            search_result = client.search_issues(
              query: "repo:#{org}/#{repo} is:open label:autofix #{exception_class}"
            )
            items = search_result.dig(:result, :items) || []

            if items.any?
              update_existing_issue(client: client, issue: items.first, events: events, org: org, repo: repo)
            else
              ctx = build_issue_context(cluster: cluster, events: events, exception_class: exception_class)
              open_new_issue(client: client, cluster: cluster, org: org, repo: repo, ctx: ctx)
            end
          rescue StandardError => e
            { success: false, reason: e.message }
          end

          private

          def update_existing_issue(client:, issue:, events:, org:, repo:)
            issue_number = issue[:number]
            issue_body   = issue[:body].to_s
            caller_locations = events.map { |e| "#{e[:caller_file]}:#{e[:caller_line]}" }
            new_locations = caller_locations.reject { |loc| issue_body.include?(loc) }

            if new_locations.any?
              comment_body = "**Additional caller locations observed:**\n\n" \
                             "#{new_locations.map { |l| "- #{l}" }.join("\n")}"
              client.create_comment(owner: org, repo: repo, issue_number: issue_number, body: comment_body)
              { success: true, action: :commented, issue_number: issue_number }
            else
              { success: true, action: :skipped, issue_number: issue_number }
            end
          end

          def build_issue_context(cluster:, events:, exception_class:)
            first = events.first
            {
              exception_class:  exception_class,
              caller_locations: events.map { |e| "#{e[:caller_file]}:#{e[:caller_line]}" },
              occurrences:      events.size,
              first_seen:       first[:first_seen] || 'unknown',
              message:          first[:message],
              backtrace_lines:  (first[:backtrace] || []).first(5).map { |l| "    #{l}" }.join("\n"),
              diagnosis:        cluster[:diagnosis] || cluster[:summary]
            }
          end

          def open_new_issue(client:, cluster:, org:, repo:, ctx:)
            body = <<~BODY
              ## autofix report

              **Exception**: `#{ctx[:exception_class]}`
              **Source**: #{ctx[:caller_locations].first}
              **Occurrences**: #{ctx[:occurrences]}
              **First seen**: #{ctx[:first_seen]}

              ### Error Details

              ```
              #{ctx[:message]}
              ```

              ### Backtrace (top 5)

              ```
              #{ctx[:backtrace_lines]}
              ```

              ### Caller Locations

              #{ctx[:caller_locations].map { |l| "- #{l}" }.join("\n")}

              ### Diagnosis

              #{ctx[:diagnosis]}
            BODY

            result = client.create_issue(
              owner:  org,
              repo:   repo,
              title:  "autofix: #{cluster[:summary]}",
              body:   body,
              labels: ['autofix']
            )

            issue_data = result[:result] || {}
            { success: true, action: :created, issue_number: issue_data[:number], url: issue_data[:html_url] }
          end
        end
      end
    end
  end
end

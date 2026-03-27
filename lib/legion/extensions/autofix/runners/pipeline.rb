# frozen_string_literal: true

require_relative 'triage'
require_relative 'diagnose'
require_relative 'fix'
require_relative 'ship'
require_relative '../helpers/batch_buffer'

module Legion
  module Extensions
    module Autofix
      module Runners
        module Pipeline
          include Legion::Extensions::Helpers::Lex if defined?(Legion::Extensions::Helpers::Lex)
          include Triage
          include Diagnose
          include Fix
          include Ship

          def self.buffer
            @buffer ||= begin
              window   = Legion::Settings.dig(:autofix, :batch, :window_seconds)  rescue nil # rubocop:disable Style/RescueModifier
              count    = Legion::Settings.dig(:autofix, :batch, :count_threshold) rescue nil # rubocop:disable Style/RescueModifier
              opts = {}
              opts[:window_seconds]  = window if window
              opts[:count_threshold] = count  if count
              Helpers::BatchBuffer.new(**opts)
            end
          end

          def handle_log_event(**event)
            fingerprint = event[:error_fingerprint]
            if fingerprint
              return { success: true, action: :skip_wip } unless cache_get("autofix:wip:#{fingerprint}").nil?
              return { success: true, action: :skip_fixed } unless cache_get("autofix:fixed:#{fingerprint}").nil?
            end

            Pipeline.buffer.add(event)
            run_pipeline if Pipeline.buffer.flush_ready?
            { success: true }
          end

          def run_pipeline
            events = Pipeline.buffer.flush!
            triage_result = batch_triage(events: events)
            return triage_result unless triage_result[:success]

            triage_result[:non_actionable].each do |cluster|
              log.info("autofix: skipping non-actionable cluster: #{cluster[:summary]}")
            end

            triage_result[:actionable].each do |cluster|
              cluster_events = events.select { |e| e[:lex] == cluster[:suggested_repo] }
              cluster_events = events if cluster_events.empty?
              process_cluster(cluster: cluster, events: cluster_events)
            end

            { success: true }
          end

          def process_cluster(cluster:, events:)
            token        = resolve_token
            org          = resolve_org
            max_retries  = resolve_max_retries
            checkout_dir = resolve_checkout_dir

            github_result = check_github(cluster: cluster, events: events, token: token, org: org)
            return github_result unless github_result[:success]

            issue_number = github_result[:issue_number]
            repo         = cluster[:suggested_repo]

            return { success: true, action: :issue_only } if github_result[:action] == :skipped

            summary  = cluster[:summary].to_s
            repo_url = "https://github.com/#{org}/#{repo}.git"
            branch   = "autofix/#{issue_number}-#{slug(summary)}"

            fix_result = attempt_fix(
              repo_url:      repo_url,
              branch:        branch,
              error_details: events.first,
              max_retries:   max_retries,
              checkout_dir:  checkout_dir
            )

            unless fix_result[:success]
              log.warn("autofix: fix failed for cluster #{cluster[:summary]}: #{fix_result[:reason]}")
              return fix_result
            end

            ship(
              checkout_path: fix_result[:checkout_path],
              owner:         org,
              repo:          repo,
              branch:        branch,
              issue_number:  issue_number,
              summary:       summary,
              token:         token,
              checkout_dir:  checkout_dir
            )
          end

          private

          def resolve_token
            Legion::Settings.dig(:autofix, :github, :token)
          rescue StandardError => e
            log.warn("autofix: could not resolve token: #{e.message}")
            nil
          end

          def resolve_org
            Legion::Settings.dig(:autofix, :github, :org) || 'LegionIO'
          rescue StandardError => e
            log.warn("autofix: could not resolve org: #{e.message}")
            'LegionIO'
          end

          def resolve_max_retries
            Legion::Settings.dig(:autofix, :llm, :max_retries) || 3
          rescue StandardError => e
            log.warn("autofix: could not resolve max_retries: #{e.message}")
            3
          end

          def resolve_checkout_dir
            Legion::Settings.dig(:autofix, :checkout_dir)
          rescue StandardError => e
            log.warn("autofix: could not resolve checkout_dir: #{e.message}")
            nil
          end

          def slug(text)
            text.to_s.downcase.gsub(/[^a-z0-9]+/, '-').slice(0, 40).chomp('-')
          end

          def cache_get(key)
            Legion::Cache.get(key) if defined?(Legion::Cache)
          end

          def cache_set(key, value, ttl: 60)
            Legion::Cache.set(key, value, ttl) if defined?(Legion::Cache)
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

require 'fileutils'
require 'securerandom'

module Legion
  module Extensions
    module Autofix
      module Helpers
        # Manages temporary git checkouts for applying and testing code fixes.
        class TempCheckout
          DEFAULT_BASE_DIR = '~/.legionio/autofix/'
          FILE_READ_CAP = 10

          def initialize(base_dir: DEFAULT_BASE_DIR)
            @base_dir = ::File.expand_path(base_dir)
            ::FileUtils.mkdir_p(@base_dir)
          end

          def clone(repo_url:, branch:)
            dir = ::File.join(@base_dir, "checkout_#{SecureRandom.hex(8)}")
            success = system('git', 'clone', '--depth', '1', repo_url, dir)
            return { success: false, reason: 'git clone failed' } unless success

            success = system('git', '-C', dir, 'checkout', '-b', branch)
            return { success: false, reason: 'git checkout -b failed' } unless success

            { success: true, path: dir }
          end

          def cleanup(path)
            expanded = ::File.expand_path(path)
            return { success: false, reason: 'path is outside base_dir' } unless under_base_dir?(expanded)

            ::FileUtils.rm_rf(expanded)
            { success: true }
          end

          def apply_edits(checkout_path:, edits:)
            edits.each do |edit|
              file_path = ::File.join(checkout_path, edit['file'])
              return { success: false, reason: "file not found: #{edit['file']}" } unless ::File.exist?(file_path)

              content = ::File.read(file_path)
              return { success: false, reason: "old string not found in #{edit['file']}" } unless content.include?(edit['old'])

              ::File.write(file_path, content.sub(edit['old'], edit['new']))
            end

            { success: true }
          end

          def read_files(checkout_path:, file_paths:)
            capped = file_paths.first(FILE_READ_CAP)
            result = {}
            capped.each do |rel_path|
              abs_path = ::File.join(checkout_path, rel_path)
              next unless ::File.exist?(abs_path)

              result[rel_path] = ::File.read(abs_path)
            end
            result
          end

          private

          def under_base_dir?(expanded_path)
            expanded_path.start_with?(@base_dir + ::File::SEPARATOR) ||
              expanded_path == @base_dir
          end
        end
      end
    end
  end
end

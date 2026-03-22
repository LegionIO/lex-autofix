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

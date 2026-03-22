# frozen_string_literal: true

require 'simplecov'
SimpleCov.start

# Stub framework dependencies for standalone spec loading
unless defined?(Legion::Extensions::Core)
  module Legion
    module Extensions
      module Core; end

      module Helpers
        module Lex; end
      end
    end

    module Logging
      def self.info(*); end
      def self.warn(*); end
      def self.error(*); end
      def self.debug(*); end
    end
  end
end

require 'legion/extensions/autofix'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.filter_run_when_matching :focus
  config.order = :random
end

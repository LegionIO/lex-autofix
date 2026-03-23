# frozen_string_literal: true

require 'simplecov'
SimpleCov.start

require 'bundler/setup'
require 'legion/logging'
require 'legion/settings'
require 'legion/cache/helper'
require 'legion/crypt/helper'
require 'legion/data/helper'
require 'legion/json/helper'
require 'legion/transport/helper'

module Legion
  module Extensions
    module Helpers
      module Lex
        include Legion::Logging::Helper
        include Legion::Settings::Helper
        include Legion::Cache::Helper
        include Legion::Crypt::Helper
        include Legion::Data::Helper
        include Legion::JSON::Helper
        include Legion::Transport::Helper
      end
    end

    module Actors
      class Every
        include Helpers::Lex
      end

      class Once
        include Helpers::Lex
      end
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

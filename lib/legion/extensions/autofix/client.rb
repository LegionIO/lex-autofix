# frozen_string_literal: true

require_relative 'helpers/client'
require_relative 'runners/triage'
require_relative 'runners/diagnose'
require_relative 'runners/fix'
require_relative 'runners/ship'

module Legion
  module Extensions
    module Autofix
      class Client
        include Helpers::Client
        include Runners::Triage
        include Runners::Diagnose
        include Runners::Fix
        include Runners::Ship

        attr_reader :opts

        def initialize(github_token: nil, github_org: 'LegionIO', checkout_dir: nil, **extra)
          @opts = { github_token: github_token, github_org: github_org, checkout_dir: checkout_dir, **extra }
        end
      end
    end
  end
end

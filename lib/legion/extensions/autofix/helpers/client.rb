# frozen_string_literal: true

module Legion
  module Extensions
    module Autofix
      module Helpers
        module Client
          def settings
            { options: @opts }
          end
        end
      end
    end
  end
end

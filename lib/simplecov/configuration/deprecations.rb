# frozen_string_literal: true

require_relative "../deprecation"

module SimpleCov
  module Configuration
    DEPRECATION_MODES = Deprecation::MODES

    # The configuration DSL migrates by warn-and-delegate, which means a project
    # can run on deprecated spellings indefinitely without noticing.
    # `deprecations :raise` turns every deprecated API into a ConfigurationError,
    # so a project that has migrated can guard in CI against old spellings
    # creeping back. There is deliberately no silencing mode: a deprecation you
    # cannot see is a migration you never make.
    def deprecations(mode = nil)
      return Deprecation.mode unless mode

      Deprecation.mode = mode
    end
  end
end

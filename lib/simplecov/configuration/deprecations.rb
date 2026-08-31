# frozen_string_literal: true

module SimpleCov
  module Configuration
    DEPRECATION_MODES = %i[warn raise].freeze

    # The configuration DSL migrates by warn-and-delegate, which means a project
    # can run on deprecated spellings indefinitely without noticing.
    # `deprecations :raise` turns every deprecated API into a ConfigurationError,
    # so a project that has migrated can guard in CI against old spellings
    # creeping back. There is deliberately no silencing mode: a deprecation you
    # cannot see is a migration you never make.
    def deprecations(mode = nil)
      return @deprecations ||= :warn unless mode

      unless DEPRECATION_MODES.include?(mode)
        raise ConfigurationError,
              "deprecations takes :warn or :raise, got #{mode.inspect}"
      end

      @deprecations = mode
    end
  end
end

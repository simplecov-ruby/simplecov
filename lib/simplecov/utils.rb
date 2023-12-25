# frozen_string_literal: true

module SimpleCov
  # Functionally for rounding coverage results
  module Utils
  module_function

    #
    # @api private
    #
    # Rounding down to be extra strict, see #679
    def round_coverage(coverage)
      coverage.floor(2)
    end

    def render_coverage(coverage)
      format("%.2f%%", round_coverage(coverage))
    end
  end
end

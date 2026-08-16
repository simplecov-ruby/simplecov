# frozen_string_literal: true

module SimpleCov
  class Result
    # Bundles the filter and grouping configuration a Result applies to its
    # source files after building them. Each field defaults to the SimpleCov
    # singleton's configuration, so ordinary callers never construct one;
    # tests pass a custom instance to opt out of (or extend) the project's
    # filters or groups (e.g. `filters: []` to keep every file). Grouping the
    # three together keeps Result#initialize's parameter list small.
    class FilterConfig
      attr_reader :filters, :cover_filters, :groups

      def initialize(filters: SimpleCov.filters, cover_filters: SimpleCov.cover_filters, groups: SimpleCov.groups)
        @filters = filters
        @cover_filters = cover_filters
        @groups = groups
      end
    end
  end
end

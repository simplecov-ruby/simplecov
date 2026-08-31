# frozen_string_literal: true

module SimpleCov
  class Result
    # The filter and grouping configuration a Result applies to its source files
    # after building them. Each field defaults to the SimpleCov singleton's
    # configuration, so ordinary callers never construct one; tests pass a custom
    # instance to opt out of the project's filters or groups.
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

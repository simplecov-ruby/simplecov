# frozen_string_literal: true

module SimpleCov
  # Coverage-entry filters scoped to branch / method criteria. See
  # `ignore_branches` and `ignore_methods`, and #1033 /
  # #1046 for the synthetic-entry detection rationale.
  module Configuration
    # Branch types accepted by `ignore_branches`.
    IGNORABLE_BRANCH_TYPES = %i[implicit_else eval_generated].freeze
    # Method types accepted by `ignore_methods`.
    IGNORABLE_METHOD_TYPES = %i[eval_generated].freeze

    # DEPRECATED: use `coverage(:branch) { ignore :implicit_else }`,
    # which fixes the criterion by context the way the threshold verbs
    # do. One difference rides out the deprecation period: the coverage
    # block enables the criterion it names, while this legacy setter
    # records without enabling (see #1033, #1046 for why the setting is
    # accepted regardless of enablement order).
    def ignore_branches(*types)
      SimpleCov::Deprecation.warn("`SimpleCov.ignore_branches` is deprecated. " \
                                  "Replace with `coverage(:branch) { ignore #{types.map(&:inspect).join(', ')} }`.")
      store_ignored_branches(types)
    end

    def ignored_branches
      @ignored_branches ||= []
    end

    def ignored_branch?(type)
      ignored_branches.include?(type)
    end

    # DEPRECATED: use `coverage(:method) { ignore :eval_generated }`.
    # See `ignore_branches` for the enablement difference.
    def ignore_methods(*types)
      SimpleCov::Deprecation.warn("`SimpleCov.ignore_methods` is deprecated. " \
                                  "Replace with `coverage(:method) { ignore #{types.map(&:inspect).join(', ')} }`.")
      store_ignored_methods(types)
    end

    def ignored_methods
      @ignored_methods ||= []
    end

    def ignored_method?(type)
      ignored_methods.include?(type)
    end

  private

    # The stores behind the `coverage` block's `ignore` verb and the
    # deprecated flat setters. Variadic semantics: multiple calls union,
    # duplicates are no-ops, unknown tokens raise.
    def store_ignored_branches(types)
      types.each { |type| raise_if_branch_type_unsupported(type) }
      ignored_branches.concat(types).uniq!
      ignored_branches
    end

    def store_ignored_methods(types)
      types.each { |type| raise_if_method_type_unsupported(type) }
      ignored_methods.concat(types).uniq!
      ignored_methods
    end

    def raise_if_branch_type_unsupported(type)
      return if IGNORABLE_BRANCH_TYPES.member?(type)

      raise SimpleCov::ConfigurationError,
            "Unsupported branch type #{type.inspect} for `ignore_branches`. " \
            "Supported values are #{IGNORABLE_BRANCH_TYPES.inspect}"
    end

    def raise_if_method_type_unsupported(type)
      return if IGNORABLE_METHOD_TYPES.member?(type)

      raise SimpleCov::ConfigurationError,
            "Unsupported method type #{type.inspect} for `ignore_methods`. " \
            "Supported values are #{IGNORABLE_METHOD_TYPES.inspect}"
    end
  end
end

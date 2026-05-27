# frozen_string_literal: true

module SimpleCov
  # Coverage-entry filters scoped to branch / method criteria. See
  # `ignore_branches` and `ignore_methods` for the DSL and #1033 /
  # #1046 for the synthetic-entry detection rationale.
  module Configuration
    # Branch types accepted by `ignore_branches`.
    IGNORABLE_BRANCH_TYPES = %i[implicit_else eval_generated].freeze
    # Method types accepted by `ignore_methods`.
    IGNORABLE_METHOD_TYPES = %i[eval_generated].freeze

    # Variadic; multiple calls union. Setting is recorded regardless
    # of whether branch coverage is enabled at call time. See #1033, #1046.
    def ignore_branches(*types)
      types.each { |type| raise_if_branch_type_unsupported(type) }
      ignored_branches.concat(types).uniq!
      ignored_branches
    end

    def ignored_branches
      @ignored_branches ||= []
    end

    def ignored_branch?(type)
      ignored_branches.include?(type)
    end

    # See `ignore_branches`. The only supported method-type token today
    # is `:eval_generated`; see #1046 for the rationale.
    def ignore_methods(*types)
      types.each { |type| raise_if_method_type_unsupported(type) }
      ignored_methods.concat(types).uniq!
      ignored_methods
    end

    def ignored_methods
      @ignored_methods ||= []
    end

    def ignored_method?(type)
      ignored_methods.include?(type)
    end

  private

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

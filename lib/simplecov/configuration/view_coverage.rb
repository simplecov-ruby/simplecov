# frozen_string_literal: true

module SimpleCov
  module Configuration
    DEFAULT_VIEW_GLOBS = %w[app/views/**/*.{erb,haml,slim}].freeze

    # Reports coverage for ActionView templates, defaulting to a Rails app's
    # views. Globs are expanded against `SimpleCov.root`, and one naming an
    # extension no handler is registered for (as the default does whenever a
    # project has no Haml or Slim) leaves those files out rather than reporting
    # them as empty.
    #
    # Templates the suite renders are measured through eval coverage, which this
    # enables. Templates it never renders are compiled at the end of the run so
    # they appear at 0% instead of going missing.
    def cover_views(*globs)
      globs = globs.flatten.compact
      globs = DEFAULT_VIEW_GLOBS.dup if globs.empty?
      @view_globs = globs
      enable_eval_coverage
      globs
    end

    # Nil rather than an empty Array when `cover_views` was never called, so
    # "not asked for" stays distinguishable from "asked for, with nothing to
    # match".
    def view_globs
      @view_globs
    end

    # False when eval coverage couldn't be enabled, where `cover_views` has
    # already warned and the templates would come back empty rather than at 0%.
    def view_coverage?
      !view_globs.nil? && coverage_for_eval_enabled?
    end
  end
end

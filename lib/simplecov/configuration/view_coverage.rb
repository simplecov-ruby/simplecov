# frozen_string_literal: true

module SimpleCov
  # `cover_views`, the opt-in that brings ActionView templates into the
  # report. Named for the `cover` family rather than the coverage criteria:
  # like `cover`, it says which files belong in the report, and it carries no
  # thresholds of its own. The measuring is done by eval coverage, which it
  # turns on, because a template is code the runtime evaluates rather than
  # code it loads.
  module Configuration
    DEFAULT_VIEW_GLOBS = %w[app/views/**/*.{erb,haml,slim}].freeze

    #
    # Report coverage for ActionView templates, defaulting to a Rails app's
    # views in every template language SimpleCov knows how to compile:
    #
    #   SimpleCov.start "rails" do
    #     cover_views
    #   end
    #
    # Pass globs (expanded against `SimpleCov.root`) to cover templates that
    # live elsewhere:
    #
    #   cover_views "app/views/**/*.erb", "app/components/**/*.erb"
    #
    # A glob may name an extension no handler is registered for, which the
    # default one does whenever a project has no Haml or Slim. Those files
    # are left out rather than reported as empty.
    #
    # Templates the suite renders are measured through eval coverage, which
    # this enables. Templates it never renders are compiled at the end of the
    # run so they appear at 0% instead of going missing. Ruby 3.2 or later,
    # since that is what eval coverage needs.
    #
    def cover_views(*globs)
      globs = globs.flatten.compact
      globs = DEFAULT_VIEW_GLOBS.dup if globs.empty?
      @view_globs = globs
      enable_eval_coverage
      globs
    end

    # The configured template globs, or nil when `cover_views` was never
    # called. Nil rather than an empty Array so "not asked for" stays
    # distinguishable from "asked for, with nothing to match".
    def view_globs
      @view_globs
    end

    # Whether templates should be measured. False when eval coverage couldn't
    # be enabled (Ruby 3.1 and earlier), where `cover_views` has already
    # warned and the templates would come back empty rather than at 0%.
    def view_coverage?
      !view_globs.nil? && coverage_for_eval_enabled?
    end
  end
end

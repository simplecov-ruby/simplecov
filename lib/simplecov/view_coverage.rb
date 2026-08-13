# frozen_string_literal: true

require_relative "view_coverage/template_compiler"

module SimpleCov
  #
  # Brings ActionView templates into the report, for projects that opt in with
  # `cover_views`.
  #
  # Rendering a template is already enough to measure it. ActionView compiles
  # each one with `module_eval(source, identifier, offset)` where `identifier`
  # is the template's own path, and the offset it passes cancels the `def`
  # line its wrapper adds, so eval coverage attributes the generated code back
  # to the `.erb` file at the template's own line numbers. Nothing needs
  # remapping, which is why this file is about the other half of the problem.
  #
  # A template no test renders is never compiled, so `Coverage` never hears
  # about it and the report omits it entirely. That is the flattering
  # direction to be wrong in: the views with no coverage are exactly the ones
  # that vanish. So before the result is collected, every template the run
  # didn't reach is compiled here, which lands it in the report at 0%.
  #
  module ViewCoverage
  module_function

    # Compiles every configured template the run never rendered. Returns the
    # paths that were compiled, which is also what the specs assert on.
    #
    # Called once per process, from `process_coverage_result`, immediately
    # before `Coverage.result`. It has to happen here rather than at the merge
    # point (where unloaded `.rb` files are injected) because compiling a
    # template needs ActionView, and the merging process need not have it
    # loaded. A standalone `simplecov merge` never does.
    def compile_unrendered
      return [] unless enabled?

      rendered = measured_paths
      discover.reject { |path| rendered.include?(path) }
              .select { |path| TemplateCompiler.call(path) }
    end

    # View coverage needs `enable_coverage :eval` (`cover_views` turns it on),
    # a running Coverage to record into, and ActionView to compile with.
    def enabled?
      SimpleCov.view_coverage? && Coverage.running? && TemplateCompiler.available?
    end

    # Expanded against `SimpleCov.root` rather than the working directory, and
    # filtered through the same path-only filters the rest of the report
    # honors, so `skip "app/views/admin"` keeps those templates out instead of
    # compiling them only to drop them later.
    def discover
      globs = SimpleCov.view_globs || [] #: Array[String?]
      UnloadedFileInjector.discover(globs, root: SimpleCov.root, reject: SimpleCov.filters.select(&:path_only?))
    end

    # The files `Coverage` is already holding data for, which for a template
    # means the run rendered it. `peek_result` copies the whole coverage state
    # to answer, so this stays a once-per-process call.
    def measured_paths
      Coverage.peek_result.keys.to_set
    end
  end
end

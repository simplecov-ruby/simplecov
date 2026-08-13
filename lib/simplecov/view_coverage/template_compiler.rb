# frozen_string_literal: true

module SimpleCov
  module ViewCoverage
    #
    # Compiles a single ActionView template: builds a `Template` for the file
    # on disk and defines its method into a throwaway module, without ever
    # rendering it.
    #
    # Defining the method is the whole trick. `Template#compile` hands the
    # handler's generated Ruby to `module_eval(source, identifier, offset)`,
    # and evaluating a `def` records the body as executable-but-unexecuted
    # rather than running it, so `Coverage` comes away with a zeroed line
    # array and a full set of branch tuples for the template. That is the
    # shape `SimulateCoverage` produces for a tracked `.rb` file nobody
    # required, except that here the classification comes from the runtime
    # compiling the handler's real output instead of from static analysis
    # approximating it.
    #
    # Never compile a template the suite already rendered. Evaluating the same
    # identifier a second time replaces that file's entry in `Coverage` rather
    # than adding to it, so the recompile would zero the hits the run actually
    # earned and leave a duplicate set of branch tuples behind. `ViewCoverage`
    # filters those out before calling here.
    #
    module TemplateCompiler
    module_function

      # Whether this process can compile templates at all. False in any
      # project that doesn't load ActionView, which is the common case and
      # not an error: view coverage simply has nothing to do there.
      def available?
        !defined?(::ActionView::Template).nil?
      end

      # Compiles `path`, returning whether it produced coverage data. A
      # template that doesn't compile can't render either, so the suite has
      # bigger problems than its coverage, but the report is not the place to
      # discover that and a broken view must not take the whole run down.
      def call(path)
        build_template(path, File.binread(path)).send(:compile, Module.new)
        true
      rescue StandardError, ScriptError => e
        warn "[SimpleCov]: Skipping #{path}, which did not compile (#{e.class})"
        false
      end

      # The format the template renders, taken from the extension in front of
      # the handler's: `show.html.erb` is `:html`. It reaches the handler's
      # codegen (an HTML template escapes interpolations, a text one does
      # not), but never the line structure, so a template named without one
      # compiles fine as nil.
      def format_for(path)
        segments = File.basename(path).split(".")
        return nil if segments.length < 3

        segments.fetch(-2).to_sym
      end

      # The single place ActionView is named. `handler_for_extension` is the
      # same lookup the resolver performs, so a project that has registered
      # its own handler for an extension gets that handler here too.
      #
      # simplecov:disable — needs ActionView, which the dogfood suite doesn't
      # load; covered by the rails sandbox specs, which run in a subprocess
      def build_template(path, source)
        extension = File.extname(path).delete_prefix(".")
        no_locals = [] #: Array[Symbol]
        ::ActionView::Template.new(
          source, path, ::ActionView::Template.handler_for_extension(extension),
          locals: no_locals, format: format_for(path)
        )
      end
      # simplecov:enable
    end
  end
end

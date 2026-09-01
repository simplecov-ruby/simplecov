# frozen_string_literal: true

require "pathname"

module SimpleCov
  module CLI
    # Loads a project's `.simplecov` config file purely to read configuration
    # from it, with `SimpleCov.start` and the at_exit hook installer neutered so
    # the load doesn't trigger coverage tracking. Used by the CLI to default
    # paths to whatever the project's dotfile declares, without making every
    # read-only subcommand pay for actually starting Coverage.
    module Dotfile
      extend self

      def coverage_dir
        dotfile = find
        return "coverage" unless dotfile

        with_simplecov_loaded { read_from(dotfile) }
      rescue ScriptError, StandardError => e
        # ScriptError covers the SyntaxError a malformed dotfile raises from
        # `load` (it is not a StandardError) along with LoadError; StandardError
        # covers the rest.
        warn "simplecov: failed to read coverage_dir from #{dotfile}: #{e.class}: #{e}"
        "coverage"
      end

      # Read from `.simplecov` the way `coverage_dir` is, so a project that moved
      # its baseline doesn't need `--baseline` on every ratchet.
      def baseline_file
        dotfile = find
        return Baseline::DEFAULT_FILENAME unless dotfile

        with_simplecov_loaded { read_baseline_file_from(dotfile) }
      rescue ScriptError, StandardError => e
        warn "simplecov: failed to read baseline_file from #{dotfile}: #{e.class}: #{e}"
        Baseline::DEFAULT_FILENAME
      end

      # Nil when there is no dotfile, the dotfile names no store, or it cannot be
      # read: unlike the other reads there is no sensible fallback path, and the
      # command's own missing-store error is the right answer.
      def production_coverage
        dotfile = find
        return nil unless dotfile

        with_simplecov_loaded { read_production_coverage_from(dotfile) }
      rescue ScriptError, StandardError => e
        # `warn` answers nil, which is this reader's whole fallback.
        warn "simplecov: failed to read production_coverage from #{dotfile}: #{e.class}: #{e}"
      end

      def read_production_coverage_from(dotfile)
        snapshot = SimpleCov.instance_variable_get(:@production_coverage) #: String?
        load_with_start_neutered(dotfile)
        SimpleCov.production_coverage
      ensure
        # @type var snapshot: String?
        SimpleCov.instance_variable_set(:@production_coverage, snapshot)
      end

      def read_baseline_file_from(dotfile)
        snapshot = SimpleCov.instance_variable_get(:@baseline_file) #: String?
        load_with_start_neutered(dotfile)
        SimpleCov.baseline_file
      ensure
        # @type var snapshot: String?
        SimpleCov.instance_variable_set(:@baseline_file, snapshot)
      end

      # Snapshot and restore `SimpleCov.coverage_dir` so we don't quietly clobber
      # it in a host process that's already configured. The snapshot is
      # intentionally narrow: a dotfile can still mutate other configuration
      # via `SimpleCov.configure` or `SimpleCov.start { ... }` blocks.
      def read_from(dotfile)
        snapshot = SimpleCov.instance_variable_get(:@coverage_dir) #: String?
        load_with_start_neutered(dotfile)
        SimpleCov.coverage_dir
      ensure
        # Restored even when the load raises, so a bad dotfile doesn't leave a
        # host process's configured dir clobbered.
        # @type var snapshot: String?
        SimpleCov.instance_variable_set(:@coverage_dir, snapshot)
      end

      # The nearest `.simplecov` at or above the working directory, or nil, which
      # is what the walk itself answers once it breaks at the filesystem root.
      def find
        dir = Pathname.new(Dir.pwd)
        loop do
          candidate = dir.join(".simplecov")
          return candidate.to_s if candidate.exist?
          break if dir.root?

          dir = dir.parent
        end
      end

      def with_simplecov_loaded
        previous_no_defaults = ENV.fetch("SIMPLECOV_NO_DEFAULTS", nil) #: String?
        previous_cli = ENV.fetch("SIMPLECOV_CLI", nil) #: String?
        ENV["SIMPLECOV_NO_DEFAULTS"] = "1"
        # SIMPLECOV_CLI lets a project's `.simplecov` opt some config into
        # CLI-only behavior: simplecov itself sets `coverage_dir` to the dogfood
        # path here but skips that for descendants.
        ENV["SIMPLECOV_CLI"] = "1"
        load_simplecov
        yield
      ensure
        # @type var previous_no_defaults: String?
        # @type var previous_cli: String?
        ENV["SIMPLECOV_NO_DEFAULTS"] = previous_no_defaults
        ENV["SIMPLECOV_CLI"] = previous_cli
      end

      # The deferred require exists for a standalone CLI process that has not
      # loaded simplecov yet. It must happen inside the env guard above, so a
      # first load here skips the default profile chain.
      def load_simplecov
        require "simplecov"
      end

      # A constant rather than a block written at the call site, where an empty
      # block and one answering nil are the same thing to every caller and so
      # to every test.
      NEUTERED = proc {}

      # Load `path` with `SimpleCov.start` and the at_exit installer turned into
      # no-ops, so a project whose dotfile calls `SimpleCov.start` doesn't
      # trigger Coverage just because we asked for `coverage_dir`. Config
      # inside any `SimpleCov.start { ... }` block still runs.
      def load_with_start_neutered(path)
        klass = SimpleCov.singleton_class
        names = %i[start_tracking install_at_exit_hook]
        stash = names.to_h { |name| [name, klass.instance_method(name)] } #: Hash[Symbol, UnboundMethod]
        # define_method over an existing method emits a "method redefined"
        # warning under $VERBOSE; the override and restore are intentional.
        silence_verbose { names.each { |name| klass.define_method(name, &(_ = NEUTERED)) } }
        load path
      ensure
        # @type var stash: Hash[Symbol, UnboundMethod]
        # @type var klass: Class
        silence_verbose { stash.each { |name, method| klass.define_method(name, method) } }
      end

      def silence_verbose
        previous = $VERBOSE #: bool?
        $VERBOSE = nil
        yield
      ensure
        # @type var previous: bool?
        $VERBOSE = previous
      end
    end
  end
end

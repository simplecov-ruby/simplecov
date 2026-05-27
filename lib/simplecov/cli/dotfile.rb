# frozen_string_literal: true

require "pathname"

module SimpleCov
  module CLI
    # Loads a project's `.simplecov` config file purely to read
    # `coverage_dir` from it, with `SimpleCov.start` and the at_exit
    # hook installer neutered so the load doesn't trigger coverage
    # tracking. Used by the CLI to default `--input` / `--report`
    # paths to whatever the project's dotfile declares, without making
    # every read-only subcommand pay for actually starting Coverage.
    module Dotfile
    module_function

      def coverage_dir
        dotfile = find
        return "coverage" unless dotfile

        with_simplecov_loaded { read_from(dotfile) }
      rescue LoadError, StandardError => e
        # simplecov:disable — defensive fallback for a bad dotfile (parse
        # error, EACCES, etc.); never fires in the project's own dogfood run
        warn "simplecov: failed to read coverage_dir from #{dotfile}: #{e.class}: #{e.message}"
        "coverage"
        # simplecov:enable
      end

      # Load the dotfile, snapshot+restore `SimpleCov.coverage_dir` so we
      # don't quietly clobber it in a host process that's already
      # configured (e.g. when the CLI is exercised inline by simplecov's
      # own spec suite). The snapshot is intentionally narrow: a dotfile
      # can still mutate other SimpleCov configuration (filters, groups,
      # formatters, command_name, ...) via `SimpleCov.configure` or
      # `SimpleCov.start { ... }` blocks. The CLI normally runs as a
      # top-level process where that's harmless; callers driving it from
      # inside a Ruby host that cares about isolation should arrange that
      # themselves.
      def read_from(dotfile)
        snapshot = SimpleCov.instance_variable_get(:@coverage_dir)
        load_with_start_neutered(dotfile)
        dir = SimpleCov.coverage_dir
        SimpleCov.instance_variable_set(:@coverage_dir, snapshot)
        dir
      end

      def find
        dir = Pathname.new(Dir.pwd)
        loop do
          candidate = dir.join(".simplecov")
          return candidate.to_s if candidate.exist?
          break if dir.root?

          dir = dir.parent
        end
        nil
      end

      def with_simplecov_loaded
        previous_no_defaults = ENV.fetch("SIMPLECOV_NO_DEFAULTS", nil)
        previous_cli         = ENV.fetch("SIMPLECOV_CLI", nil)
        ENV["SIMPLECOV_NO_DEFAULTS"] = "1"
        # SIMPLECOV_CLI lets a project's `.simplecov` opt some config into
        # CLI-only behavior — e.g. simplecov itself sets `coverage_dir`
        # to the dogfood path here but skips that for descendants.
        ENV["SIMPLECOV_CLI"] = "1"
        require "simplecov"
        yield
      ensure
        ENV["SIMPLECOV_NO_DEFAULTS"] = previous_no_defaults
        ENV["SIMPLECOV_CLI"]         = previous_cli
      end

      # Load `path` with `SimpleCov.start` and the at_exit installer
      # turned into no-ops, so a project whose dotfile calls
      # `SimpleCov.start` doesn't trigger Coverage just because we asked
      # for `coverage_dir`. Config inside any `SimpleCov.start { ... }`
      # block still runs.
      def load_with_start_neutered(path)
        klass = SimpleCov.singleton_class
        names = %i[start_tracking install_at_exit_hook]
        stash = names.to_h { |name| [name, klass.instance_method(name)] }
        # define_method over an existing method emits a "method redefined"
        # warning under $VERBOSE; the override and restore are intentional.
        silence_verbose { names.each { |name| klass.define_method(name) { nil } } }
        load path
      ensure
        silence_verbose { stash.each { |name, method| klass.define_method(name, method) } }
      end

      def silence_verbose
        previous = $VERBOSE
        $VERBOSE = nil
        yield
      ensure
        $VERBOSE = previous
      end
    end
  end
end

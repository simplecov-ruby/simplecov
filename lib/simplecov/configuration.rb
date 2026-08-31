# frozen_string_literal: true

require "fileutils"

module SimpleCov
  module Configuration
    def root(root = nil)
      return @root if instance_variable_defined?(:@root) && root.nil?

      self.root = root
      @root
    end

    # nil means the working directory, the default the reader would have derived.
    def root=(root)
      @coverage_path = nil unless @coverage_path_explicit # invalidate cache
      @root = File.expand_path(root || Dir.getwd)
    end

    def coverage_dir(dir = nil)
      return @coverage_dir if instance_variable_defined?(:@coverage_dir) && dir.nil?

      self.coverage_dir = dir
      @coverage_dir
    end

    # nil means the default 'coverage', recorded as a derivation rather than a
    # choice.
    def coverage_dir=(dir)
      @coverage_path = nil unless @coverage_path_explicit # invalidate cache
      @coverage_dir_explicit = true unless dir.nil?
      @coverage_dir = dir || "coverage"
    end

    #
    # Defaults to `SimpleCov.root` + `SimpleCov.coverage_dir`, but callers can
    # override with an arbitrary absolute path, handy for out-of-tree build
    # directories (#716).
    #
    # Reading is pure: the directory is only created when a path is explicitly
    # assigned. The codepaths that write into it ensure existence themselves,
    # so read-only CLI subcommands that interpolate the path into status text
    # don't materialize a stray `coverage/` directory.
    #
    def coverage_path(path = nil)
      self.coverage_path = path if path

      @coverage_path ||= File.expand_path(coverage_dir, root)
    end

    # Assigning is the signal the caller intends to write there, so the
    # directory is created.
    def coverage_path=(path)
      expanded = File.expand_path(path)
      @coverage_path = expanded
      @coverage_path_explicit = true
      FileUtils.mkdir_p expanded
    end

    #
    # The name of the command (a.k.a. Test Suite) currently running. Used for
    # result merging and caching. Auto-detected.
    #
    def command_name(name = nil)
      self.command_name = name unless name.nil?
      @command_name ||= CommandGuesser.guess
    end

    def command_name=(name)
      @command_name = name
    end

    def profiles
      @profiles ||= Profiles.new
    end

    #
    # Configure simplecov in a block instead of prepending SimpleCov to each
    # config method. Parameterized blocks retain their caller context and
    # receive this configuration target explicitly.
    #
    def configure(&block)
      raise ArgumentError, "configuration block required" unless block

      if block.parameters.empty?
        instance_exec(&(_ = block))
      else
        yield self
      end
      self
    end

    def at_exit(&block)
      @at_exit = block if block
      configured = @at_exit
      return configured if configured
      return -> {} unless active_session?

      @at_exit = lambda do
        result = SimpleCov.result
        result.format! if result && SimpleCov.merge_finalization_owner?
      end
    end

    # The Coverage module is actively tracking, or a `@result` has already been
    # assembled (`SimpleCov.collate` never starts Coverage).
    def active_session?
      !!SimpleCov.result? || coverage_running?
    end

    # A configuration loaded on its own may have no Coverage to ask, which is
    # not something a suite that measures coverage can be.
    def coverage_running?
      defined?(Coverage) ? Coverage.running? : false
    end

    def at_fork(&block)
      @at_fork = block if block
      @at_fork ||= lambda { |_pid|
        # Needs a name that's unique per worker within a run yet identical across
        # runs. Built from SimpleCov's stable fork serial rather than the OS pid:
        # with the pid, every run produced uniquely-named results that never
        # overwrote the previous run's, so they piled up in .resultset.json
        # until merge_timeout and the merged report's file set drifted from run
        # to run (#1171).
        SimpleCov.command_name "#{SimpleCov.command_name} (subprocess: #{SimpleCov.subprocess_serial})"
        SimpleCov.print_errors false
        SimpleCov.formatter Formatter::SimpleFormatter
        SimpleCov.minimum_coverage 0
        SimpleCov.start
      }
    end

    # Only a String renames, and a name already chosen survives anything else.
    def project_name(new_name = nil)
      @project_name = new_name if new_name.is_a?(String)
      @project_name ||= File.basename(root).capitalize.tr("_", " ")
    end
  end
end

require_relative "configuration/coverage"
require_relative "configuration/coverage_criteria"
require_relative "configuration/eval_coverage"
require_relative "configuration/filters"
require_relative "configuration/groups"
require_relative "configuration/formatting"
require_relative "configuration/ignored_entries"
require_relative "configuration/merging"
require_relative "configuration/test_tracking"
require_relative "configuration/thresholds"
require_relative "configuration/baseline"
require_relative "configuration/deprecations"
require_relative "configuration/history"
require_relative "configuration/missed_caps"
require_relative "configuration/production"
require_relative "configuration/view_coverage"

# frozen_string_literal: true

require "fileutils"

module SimpleCov
  #
  # Bundles the configuration options used for SimpleCov. All methods
  # defined here are usable from SimpleCov directly. Please check out
  # SimpleCov documentation for further info.
  #
  module Configuration
    #
    # The root for the project. This defaults to the
    # current working directory.
    #
    # Configure with SimpleCov.root('/my/project/path')
    #
    def root(root = nil)
      return @root if defined?(@root) && root.nil?

      @coverage_path = nil unless @coverage_path_explicit # invalidate cache
      @root = File.expand_path(root || Dir.getwd)
    end

    #
    # The name of the output and cache directory. Defaults to 'coverage'
    #
    # Configure with SimpleCov.coverage_dir('cov')
    #
    def coverage_dir(dir = nil)
      return @coverage_dir if defined?(@coverage_dir) && dir.nil?

      @coverage_path = nil unless @coverage_path_explicit # invalidate cache
      @coverage_dir_explicit = true unless dir.nil?
      @coverage_dir = dir || "coverage"
    end

    #
    # Returns the full path to the output directory. By default
    # constructed from `SimpleCov.root` + `SimpleCov.coverage_dir`, but
    # callers can override with an arbitrary absolute path — handy for
    # out-of-tree build directories. See #716.
    #
    # Reading is pure: the directory is only created when a path is
    # explicitly assigned (the user has signaled they intend to write
    # there). The codepaths that actually write into the directory
    # (formatters, `LastRun`, `ResultsetStore`) ensure existence
    # themselves, so read-only CLI subcommands that interpolate the
    # path into status text don't materialize a stray `coverage/`
    # directory.
    #
    def coverage_path(path = nil)
      if path
        expanded = File.expand_path(path)
        @coverage_path = expanded
        @coverage_path_explicit = true
        FileUtils.mkdir_p expanded
      end

      @coverage_path ||= File.expand_path(coverage_dir, root)
    end

    #
    # The name of the command (a.k.a. Test Suite) currently running.
    # Used for result merging and caching. Auto-detected; set explicitly
    # with SimpleCov.command_name("test:units").
    #
    def command_name(name = nil)
      @command_name = name unless name.nil?
      @command_name ||= SimpleCov::CommandGuesser.guess
    end

    # Returns the hash of available profiles
    def profiles
      @profiles ||= SimpleCov::Profiles.new
    end

    #
    # Allows you to configure simplecov in a block instead of
    # prepending SimpleCov to each config method. Parameterized blocks retain
    # their caller context and receive this configuration target explicitly.
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

    #
    # Gets or sets the behavior to process coverage results.
    # By default, it stores/merges the current result and formats only
    # from the final reporting process.
    #
    def at_exit(&block)
      @at_exit = block if block
      configured = @at_exit
      return configured if configured
      return proc {} unless active_session?

      @at_exit = proc do
        result = SimpleCov.result
        result.format! if result && SimpleCov.merge_finalization_owner?
      end
    end

    # Whether SimpleCov has anything to do at exit: the Coverage module
    # is actively tracking, or a `@result` has already been assembled
    # (e.g. by `SimpleCov.collate`, which never starts Coverage).
    def active_session?
      SimpleCov.result? || (defined?(Coverage) && Coverage.running?)
    end

    #
    # Gets or sets the behavior to start a new forked Process.
    # Defaults to adding " (subprocess: #{serial})" to command_name and
    # starting SimpleCov in quiet mode.
    #
    def at_fork(&block)
      @at_fork = block if block
      @at_fork ||= lambda { |_pid|
        # Needs a name that's unique per worker within a run yet identical
        # across runs. Build it from SimpleCov's stable fork serial rather
        # than the OS pid: with the pid, every run produced uniquely-named
        # results that never overwrote the previous run's, so they piled up
        # in .resultset.json until merge_timeout and the merged report's
        # file set drifted from run to run. See issue #1171.
        SimpleCov.command_name "#{SimpleCov.command_name} (subprocess: #{SimpleCov.subprocess_serial})"
        # be quiet, the parent process will use the regular formatter
        SimpleCov.print_errors false
        SimpleCov.formatter SimpleCov::Formatter::SimpleFormatter
        SimpleCov.minimum_coverage 0
        SimpleCov.start
      }
    end

    #
    # Returns the project name — defaults to the last dirname in
    # SimpleCov.root, capitalized with underscores → spaces.
    #
    def project_name(new_name = nil)
      current = defined?(@project_name) ? @project_name : nil
      return current if current && new_name.nil?

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
require_relative "configuration/view_coverage"

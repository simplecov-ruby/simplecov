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
        @coverage_path = File.expand_path(path)
        @coverage_path_explicit = true
        FileUtils.mkdir_p @coverage_path
      end

      @coverage_path ||= File.expand_path(coverage_dir, root)
    end

    #
    # The name of the command (a.k.a. Test Suite) currently running.
    # Used for result merging and caching. Auto-detected; set explicitly
    # with SimpleCov.command_name("test:units").
    #
    def command_name(name = nil)
      @name = name unless name.nil?
      @name ||= SimpleCov::CommandGuesser.guess
      @name
    end

    # Returns the hash of available profiles
    def profiles
      @profiles ||= SimpleCov::Profiles.new
    end

    #
    # Allows you to configure simplecov in a block instead of
    # prepending SimpleCov to each config method.
    #
    def configure(&block)
      block_context = block.binding.receiver

      # If the block was defined in our own context, instance_exec is sufficient
      return instance_exec(&block) if equal?(block_context)

      # Copy the caller's instance variables in so that references like @filter
      # inside the block resolve to the caller's values, not ours.
      saved = swap_ivars_from(block_context)
      instance_exec(&block)
    ensure
      restore_ivars(block_context, saved) if defined?(saved) && saved
    end

    #
    # Gets or sets the behavior to process coverage results.
    # By default, it stores/merges the current result and formats only
    # from the final reporting process.
    #
    def at_exit(&block)
      @at_exit = block if block
      return @at_exit if @at_exit
      return proc {} unless active_session?

      @at_exit = proc do
        result = SimpleCov.result
        result.format! if result && SimpleCov.final_result_process?
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
      return @project_name if defined?(@project_name) && @project_name && new_name.nil?

      @project_name = new_name if new_name.is_a?(String)
      @project_name ||= File.basename(root).capitalize.tr("_", " ")
    end

  private

    # Copy instance variables from block_context into self, saving any
    # of ours that would be clobbered. Returns the saved values for
    # later restoration.
    def swap_ivars_from(block_context)
      saved = {}
      our_ivars = instance_variables
      block_context.instance_variables.each do |ivar|
        saved[ivar] = instance_variable_get(ivar) if our_ivars.include?(ivar)
        instance_variable_set(ivar, block_context.instance_variable_get(ivar))
      end
      saved
    end

    # Copy instance variables back to block_context and restore our saved values.
    def restore_ivars(block_context, saved)
      block_context.instance_variables.each do |ivar|
        block_context.instance_variable_set(ivar, instance_variable_get(ivar))
      end
      saved.each { |ivar, value| instance_variable_set(ivar, value) }
    end
  end
end

require_relative "configuration/coverage"
require_relative "configuration/coverage_criteria"
require_relative "configuration/filters"
require_relative "configuration/formatting"
require_relative "configuration/ignored_entries"
require_relative "configuration/merging"
require_relative "configuration/thresholds"

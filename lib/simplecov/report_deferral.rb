# frozen_string_literal: true

# The clobber-prevention backstop: an empty process stands down instead of
# formatting over a fresher report a sibling produced. Typically fires when
# `SimpleCov.start` ran in a parent process that shelled out to the test runner
# (#581).

module SimpleCov
  class << self
    def defer_to_existing_report?
      return false unless existing_report_newer_than_us?

      res = result
      empty = res.nil? || res.files.empty?
      warn_about_deferred_report if empty
      empty
    end

    # `.last_run.json` only exists after fully successful runs, so alone it left
    # the backstop inert when the child run failed, the case where clobbering its
    # report hurts most. The report stamp is touched by every formatting process
    # regardless of exit status. The rescue covers a file vanishing mid-at_exit.
    def existing_report_newer_than_us?
      return false unless process_start_time

      [LastRun.last_run_path, ReportStamp.path].any? do |path|
        File.mtime(path) > process_start_time
      rescue SystemCallError
        false
      end
    end

    def warn_about_deferred_report
      return unless print_errors

      ExitCodes.print_error Color.colorize(
        "Skipping SimpleCov report — this process tracked no application code and a newer " \
        "report already exists at #{coverage_path}. This usually means SimpleCov.start ran in a " \
        "parent process (e.g. a Rakefile or Rails' Bundler.require) that shelled out to the test " \
        "runner. See https://github.com/simplecov-ruby/simplecov/issues/581.",
        :yellow
      )
    end
  end
end

# frozen_string_literal: true

require_relative "base"
require_relative "../atomic_file"

module SimpleCov
  module Formatter
    # Auto-ratchets the per-file coverage baseline (see
    # `SimpleCov::Baseline` and `simplecov ratchet`) as a formatter, for
    # teams that want floors to tighten on every run instead of by
    # deliberate `simplecov ratchet` invocations:
    #
    #   SimpleCov.start do
    #     formats :html, :baseline
    #   end
    #
    # The semantics are exactly the CLI's: the first run generates a
    # floor for every reported file, later runs raise the floors of
    # files that improved, keep the floors of files that regressed
    # (naming them in the status line), prune entries for files the
    # report no longer carries, and never add entries for new files, so
    # new code stays answerable to the global thresholds. The file is
    # rewritten only when a floor actually moved, so a run that changes
    # nothing leaves the working tree clean.
    #
    # The exit checks still judge the run against the floors as they
    # were when it started (the baseline is read once per path), and
    # ratcheting never loosens a floor, so tightening before the checks
    # cannot flip a failing file to passing. The trade-off of the
    # auto mode is that floors tighten without a human in the loop;
    # the diff still lands in the working tree for the commit to carry.
    class BaselineFormatter < Base
      # The status line for a baseline run is the ratchet's own summary
      # rather than anything read off the result, so the summary is what
      # `emit_status` is handed in the result's place.
      def format(result)
        emit_status(ratchet(result))
      end

    private

      # Ratchet against the checked-in floors, or generate them all on
      # the first run, writing only when something moved.
      def ratchet(result)
        current = current_floors(result)
        existing = SimpleCov.baseline
        return generate(current) unless existing

        outcome = existing.ratchet(current)
        changed = outcome.tightened.any? || outcome.pruned.any?
        write(outcome.baseline) if changed
        note = summary(outcome, changed)
        regressed = outcome.regressed
        regressed.empty? ? note : "#{note}#{below_floors(regressed)}"
      end

      def generate(current)
        baseline = Baseline.generate(current)
        write(baseline)
        files = baseline.entries.size
        "Coverage baseline generated to #{displayable_output_path} (#{files} #{files.eql?(1) ? 'file' : 'files'})"
      end

      def summary(outcome, changed)
        return "Coverage baseline unchanged at #{displayable_output_path}" unless changed

        "Coverage baseline ratcheted to #{displayable_output_path} " \
          "(#{outcome.tightened.size} tightened, #{outcome.pruned.size} pruned)"
      end

      # Regressed floors are kept, not loosened, so they stay worth
      # saying out loud: these are the files the exit check fails. The
      # caller keeps the empty case, so this always has something to
      # name.
      def below_floors(regressed)
        noun = regressed.size.eql?(1) ? "1 file below its floor" : "#{regressed.size} files below their floors"
        ", #{noun}: #{regressed.join(', ')}"
      end

      # The measured state in the shape `Baseline#ratchet` and
      # `Baseline.generate` take, covering only the criteria the run
      # measured. `SourceFile#coverage_statistics` answers for disabled
      # criteria too (as empty statistics), so the criteria are gated on
      # the configuration rather than on the stats' presence.
      def current_floors(result)
        criteria = measured_criteria
        floors = {} #: Baseline::current_floors
        result.files.each do |file|
          floors[file.project_filename] = criteria.to_h { |criterion| [criterion, floor_of(file, criterion)] }
        end
        floors
      end

      def measured_criteria
        criteria = [] #: Array[Symbol]
        criteria << :line if SimpleCov.line_coverage?
        criteria << :branch if SimpleCov.branch_coverage?
        criteria << :method if SimpleCov.method_coverage?
        criteria
      end

      def floor_of(file, criterion)
        stats = file.coverage_statistics(criterion)
        {percent: SimpleCov.round_coverage(stats.percent), missed: stats.missed}
      end

      def write(baseline)
        AtomicFile.write(output_path, baseline.to_yaml)
      end

      # The baseline lives where the exit check reads it, not under the
      # coverage directory: it is checked-in policy, not a report
      # artifact.
      def output_path
        File.expand_path(SimpleCov.baseline_file, SimpleCov.root)
      end

      # `format` hands the ratchet's summary to `emit_status`, which
      # passes it through to here.
      def output_message(message)
        message
      end
    end
  end
end

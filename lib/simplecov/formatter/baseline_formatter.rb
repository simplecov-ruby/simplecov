# frozen_string_literal: true

require_relative "base"
require_relative "../atomic_file"

module SimpleCov
  module Formatter
    # Auto-ratchets the per-file coverage baseline as a formatter, for teams
    # that want floors to tighten on every run instead of by deliberate
    # `simplecov ratchet` invocations. The semantics are exactly the CLI's, and
    # the file is rewritten only when a floor actually moved.
    #
    # The exit checks still judge the run against the floors as they were when
    # it started (the baseline is read once per path), and ratcheting never
    # loosens a floor, so tightening before the checks cannot flip a failing
    # file to passing.
    class BaselineFormatter < Base
      def format(result)
        emit_status(ratchet(result))
      end

    private

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

      def below_floors(regressed)
        noun = regressed.size.eql?(1) ? "1 file below its floor" : "#{regressed.size} files below their floors"
        ", #{noun}: #{regressed.join(', ')}"
      end

      # `SourceFile#coverage_statistics` answers for disabled criteria too, as
      # empty statistics, so the criteria are gated on the configuration rather
      # than on the stats' presence.
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

      # The baseline lives where the exit check reads it, not under the coverage
      # directory: it is checked-in policy, not a report artifact.
      def output_path
        File.expand_path(SimpleCov.baseline_file, SimpleCov.root)
      end

      # `format` hands the ratchet's summary to `emit_status`, which passes it
      # through to here in the result's place.
      def output_message(message)
        message
      end
    end
  end
end

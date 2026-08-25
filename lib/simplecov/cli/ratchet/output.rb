# frozen_string_literal: true

module SimpleCov
  module CLI
    module Ratchet
      # Renders a ratchet pass: the one-line write summary, the
      # below-floor note, and the JSON form of the same facts.
      module Output
      module_function

        def emit(stdout, opts, outcome, generated)
          return stdout.puts(JSON.generate(json_summary(opts, outcome, generated))) if opts[:json]

          verb = opts[:dry_run] ? "would write" : "wrote"
          stdout.puts("simplecov ratchet: #{verb} #{opts[:baseline]} (#{change_summary(outcome, generated)})")
          report_regressed(stdout, outcome.regressed)
        end

        def change_summary(outcome, generated)
          files = outcome.baseline.entries.size
          return "#{files} #{files == 1 ? 'file' : 'files'}" if generated

          "#{outcome.tightened.size} tightened, #{outcome.pruned.size} pruned, #{outcome.unchanged.size} unchanged"
        end

        # Floors are kept, not loosened, so a regressed file stays worth
        # saying out loud: running the suite is what shows the failures.
        def report_regressed(stdout, regressed)
          return if regressed.empty?

          noun = regressed.size == 1 ? "1 file below its floor" : "#{regressed.size} files below their floors"
          stdout.puts("simplecov ratchet: #{noun}, entries kept unchanged")
        end

        def json_summary(opts, outcome, generated)
          {
            written: !opts[:dry_run], path: opts[:baseline], generated: generated,
            files: outcome.baseline.entries.size,
            tightened: outcome.tightened, pruned: outcome.pruned,
            regressed: outcome.regressed, unchanged: outcome.unchanged
          }
        end
      end
    end
  end
end

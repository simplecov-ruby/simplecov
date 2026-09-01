# frozen_string_literal: true

module SimpleCov
  module CLI
    module Ratchet
      module Output
        extend CommandHelpers

        extend self

        def emit(stdout, opts, outcome, generated)
          return stdout.puts(JSON.generate(json_summary(opts, outcome, generated))) if opts.fetch(:json)

          verb = opts.fetch(:dry_run) ? "would write" : "wrote"
          stdout.puts("simplecov ratchet: #{verb} #{opts.fetch(:baseline)} (#{change_summary(outcome, generated)})")
          report_regressed(stdout, outcome.regressed)
        end

        def change_summary(outcome, generated)
          files = outcome.baseline.entries.size
          return "#{files} #{one?(files) ? "file" : "files"}" if generated

          "#{outcome.tightened.size} tightened, #{outcome.pruned.size} pruned, #{outcome.unchanged.size} unchanged"
        end

        def report_regressed(stdout, regressed)
          return if regressed.empty?

          noun = one?(regressed.size) ? "1 file below its floor" : "#{regressed.size} files below their floors"
          stdout.puts("simplecov ratchet: #{noun}, entries kept unchanged")
        end

        def json_summary(opts, outcome, generated)
          {
            written: !opts.fetch(:dry_run), path: opts.fetch(:baseline), generated: generated,
            files: outcome.baseline.entries.size,
            tightened: outcome.tightened, pruned: outcome.pruned,
            regressed: outcome.regressed, unchanged: outcome.unchanged
          }
        end
      end
    end
  end
end

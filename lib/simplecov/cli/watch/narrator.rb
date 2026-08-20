# frozen_string_literal: true

module SimpleCov
  module CLI
    module Watch
      # The session's voice: the watching/serving banner, the
      # "<file> changed, running N files..." line, and the result
      # percentage with its delta that joins the same line.
      class Narrator
        def initialize(stdout, root)
          @stdout = stdout
          @root = root
        end

        def banner(server, count)
          host = Serve.url_host(server.addr[3])
          @stdout.puts("watching #{count} file#{'s' unless count == 1}, " \
                       "serving http://#{host}:#{server.addr[1]}/")
          @stdout.puts("Press Ctrl-C to stop.")
        end

        def change(changed, plan)
          named = name(changed)
          return @stdout.puts("#{named} changed, no recorded test touches it") unless plan[:run]

          @stdout.print("#{named} changed, #{action(plan[:tests])}...")
        end

        # " 95.00% (+5.00%)" on the line `change` opened.
        def result(before, after)
          return @stdout.puts unless after

          delta = before ? format(" (%+.2f%%)", after - before) : ""
          @stdout.puts(format(" %.2f%%", after) + delta)
        end

        def failed_refresh
          @stdout.puts(" the report did not regenerate")
        end

        def stopping
          @stdout.puts("\nsimplecov watch: stopping")
        end

      private

        def name(changed)
          relative = changed.map { |path| path.delete_prefix("#{@root}/") }
          relative.size == 1 ? relative.first : "#{relative.first} and #{relative.size - 1} more"
        end

        def action(tests)
          tests ? "running #{tests.size} file#{'s' unless tests.one?}" : "running the full suite"
        end
      end
    end
  end
end

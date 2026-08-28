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
          host = Serve.url_host(server.addr.fetch(3))
          @stdout.puts("watching #{count} file#{'s' unless count.eql?(1)}, " \
                       "serving http://#{host}:#{server.addr.fetch(1)}/")
          @stdout.puts("Press Ctrl-C to stop.")
        end

        def change(changed, plan)
          named = name(changed)
          return @stdout.puts("#{named} changed, no recorded test touches it") unless plan.fetch(:run)

          @stdout.print("#{named} changed, #{action(plan.fetch(:tests))}...")
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

        # A burst is named by the file that opened it, so the line stays
        # one line however many files a save touched.
        def name(changed)
          relative = changed.map { |path| path.delete_prefix("#{@root}/") }
          named = relative.first
          relative.size.eql?(1) ? named : "#{named} and #{relative.size - 1} more"
        end

        def action(tests)
          tests ? "running #{tests.size} file#{'s' unless tests.one?}" : "running the full suite"
        end
      end
    end
  end
end

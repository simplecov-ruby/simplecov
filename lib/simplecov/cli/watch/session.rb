# frozen_string_literal: true

module SimpleCov
  module CLI
    module Watch
      # One watch session: accept report connections in the background,
      # poll the tracked set for changes, re-run tests on save (selecting
      # over the recorded test map when the report carries one), and
      # push a reload to every open tab when the report regenerates.
      class Session
        # The merge window (in seconds) the child runs get through
        # SIMPLECOV_MERGE_TIMEOUT: a day, so subset re-runs keep merging
        # into a whole report across a long session instead of eroding
        # it after the default ten minutes.
        MERGE_WINDOW = "86400"

        # meta.primary_coverage names a criterion; the totals table keys
        # by its plural.
        TOTALS_KEYS = {"line" => "lines", "branch" => "branches", "method" => "methods"}.freeze

        def initialize(command:, dir:, interval:, stdout:, stderr:)
          @command = command
          @dir = dir
          @interval = interval
          @stderr = stderr
          @root = Dir.pwd
          @narrator = Narrator.new(stdout, @root)
          @live = LiveReport.new(dir)
          @poller = Poller.new
          @document = {} #: Hash[String, untyped]
        end

        def run(server)
          accept_loop(server)
          run_tests(nil) unless File.exist?(json_path)
          return 1 unless refresh

          @narrator.banner(server, @poller.size)
          poll_forever
        rescue Interrupt
          @narrator.stopping
          0
        end

        def poll_forever
          loop do
            sleep(@interval)
            step
          end
        end

        def step
          changed = settled_changes
          return if changed.empty?

          plan = plan_for(changed)
          @narrator.change(changed, plan)
          return unless plan.fetch(:run)

          before = total_percent
          run_tests(plan.fetch(:tests))
          return @narrator.failed_refresh unless refresh

          @live.broadcast
          @narrator.result(before, total_percent)
        end

      private

        # One thread accepting, one thread per connection, exactly like
        # `simplecov serve` — plus the live routes. Quiet on the EBADF /
        # IOError the closed listener raises at shutdown.
        def accept_loop(server)
          Thread.new do
            loop do
              Thread.new(server.accept) do |client|
                Serve::StaticFileHandler.handle_connection(client, @dir, @live.routes)
              end
            end
          rescue IOError, SystemCallError
            nil
          end
        end

        def plan_for(changed)
          relative = changed.map { |path| path.delete_prefix("#{@root}/") }
          TestPlan.build(relative, @document, root: @root, input: json_path, stderr: @stderr)
        end

        # The command is the project's own test invocation and must
        # produce the report itself (compose `simplecov watch simplecov
        # run ...` for a project with no SimpleCov.start hook). It gets
        # the long merge window through the environment.
        def run_tests(tests)
          env = {"SIMPLECOV_MERGE_TIMEOUT" => MERGE_WINDOW}
          # A selection is appended to the command. No selection means
          # the whole suite, which is the command on its own.
          Kernel.system(env, *(tests ? @command + tests : @command))
        end

        # Re-read the regenerated report: it is both the watch set (the
        # tracked files plus the recorded tests' files) and the totals
        # the result line diffs against. Keeps the previous document when
        # the read fails, so one bad write doesn't blind the session.
        def refresh
          document = CoverageFile.load_document(json_path, command: "watch", stderr: @stderr)
          return false unless document

          @document = document
          @poller.watch(TestPlan.watched_paths(document, @root))
          document
        end

        # Editors save in bursts, so after the first detection keep
        # polling until a full interval passes with nothing new.
        def settled_changes
          changed = @poller.changes
          return changed if changed.empty?

          loop do
            sleep(@interval)
            more = @poller.changes
            break if more.empty?

            changed |= more
          end
          changed
        end

        # The result line's one number follows the report's own primary
        # criterion (meta.primary_coverage), falling back to line
        # coverage for documents from before meta carried one.
        def total_percent
          key = TOTALS_KEYS[@document.dig("meta", "primary_coverage")] || "lines"
          value = @document.dig("total", key, "percent")
          (_ = value).to_f if value.is_a?(Numeric)
        end

        def json_path
          File.join(@dir, "coverage.json")
        end
      end
    end
  end
end

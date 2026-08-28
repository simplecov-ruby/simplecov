# frozen_string_literal: true

require "optparse"
require_relative "command_helpers"
require_relative "open"
require_relative "serve"
require_relative "affected"
require_relative "watch/poller"
require_relative "watch/live_report"
require_relative "watch/narrator"
require_relative "watch/test_plan"
require_relative "watch/session"

module SimpleCov
  module CLI
    # `simplecov watch <command...>` — the coverage inner loop: serve
    # the report the way `serve` does, poll the tracked files for saves,
    # re-run the given command on change, and push a reload to the open
    # tab over server-sent events when the report regenerates. With a
    # `track_tests` recording in the report, a save re-runs only the
    # tests that touch the changed files, by the same selection walk
    # `simplecov affected` uses; without one, every save runs the full
    # command. Child runs get a day-long merge window, so subset re-runs
    # keep merging into a whole report across a long session. The
    # command must produce the report itself; a project with no
    # SimpleCov.start hook composes `simplecov watch simplecov run ...`.
    module Watch
      extend CommandHelpers

      extend self

      def run(args, stdout:, stderr:, **)
        opts, command = parse(args)
        return error(stderr, "missing command to run (e.g. `simplecov watch bundle exec rspec`)") if command.empty?

        Serve.require_socket
        server = bind(opts, stderr)
        return 1 unless server

        serve_session(server, command, opts, stdout, stderr)
      end

      def serve_session(server, command, opts, stdout, stderr)
        launch_browser(server, stderr) if opts.fetch(:open)
        session_for(command, opts, stdout, stderr).run(server)
      ensure
        server.close
      end

      # Fire-and-forget through the same platform opener `simplecov
      # open` uses, detached so the session never waits on a browser. A
      # platform with no known opener notes the URL instead of failing
      # the watch.
      def launch_browser(server, stderr)
        url = "http://#{Serve.url_host(server.addr.fetch(3))}:#{server.addr.fetch(1)}/"
        opener = Open.browser_opener
        unless opener
          return stderr.puts("simplecov watch: no known browser opener for this platform, open it yourself: #{url}")
        end

        Process.detach(spawn(*opener, url, out: File::NULL, err: File::NULL))
      end

      # `order` (not `parse`) stops at the first positional, so the
      # runner command keeps its own flags: `simplecov watch bundle exec
      # rspec --seed 1` passes --seed through untouched.
      def parse(args)
        opts = {port: 0, host: "127.0.0.1", interval: 0.5, open: false} #: Hash[Symbol, untyped]
        rest =
          build_parser do |parser|
            parser.on("--port N", Integer)           { |v| opts[:port] = v }
            parser.on("--host HOST")                 { |v| opts[:host] = v }
            parser.on("--interval SECONDS", Float)   { |v| opts[:interval] = v }
            parser.on("--open")                      { opts[:open] = true }
          end.order(args)
        [opts, rest]
      end

      def bind(opts, stderr)
        # The receiver cast works around an rbs stdlib gap, as in serve.
        (_ = TCPServer).new(opts.fetch(:host), opts.fetch(:port)) #: TCPServer
      rescue SystemCallError, SocketError => e
        error_nil(stderr, "cannot bind to #{opts.fetch(:host)}:#{opts.fetch(:port)} (#{e})")
      end

      def session_for(command, opts, stdout, stderr)
        Session.new(command: command, dir: CLI.coverage_dir,
                    interval: opts.fetch(:interval), stdout: stdout, stderr: stderr)
      end
    end
  end
end

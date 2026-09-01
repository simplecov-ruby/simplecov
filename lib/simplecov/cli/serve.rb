# frozen_string_literal: true

require "optparse"
require_relative "command_helpers"
require_relative "serve/report_preparer"
require_relative "serve/static_file_handler"

module SimpleCov
  module CLI
    # `simplecov serve`: a small static file server backed by stdlib `socket`, so
    # there is no extra dependency just for viewing a local report on a box where
    # `file://` doesn't work. This module is the CLI wiring; the HTTP mechanics
    # live in StaticFileHandler.
    module Serve
      extend CommandHelpers

      extend self

      def run(args, stdout:, stderr:, **)
        opts = parse(args)
        dir = CLI.coverage_dir
        message = ReportPreparer.call(dir)
        return error(stderr, message) if message

        require_socket
        with_server(opts, stderr) do |server|
          announce(stdout, server, dir)
          serve_loop(server, dir, stdout)
          0
        end
      end

      # Required here rather than at load time so the other subcommands do not pay
      # for sockets.
      def require_socket
        require "socket"
      end

      # Answers 1 when the socket can't be bound: port already taken, privileged
      # port, unresolvable host. The receiver cast works around an rbs stdlib gap,
      # where TCPSocket's explicit `self.new` shadows TCPServer#initialize's
      # (host, port) form.
      def with_server(opts, stderr)
        server = (_ = TCPServer).new(opts.fetch(:host), opts.fetch(:port)) #: TCPServer
      rescue SystemCallError, SocketError => e
        error(stderr, "cannot bind to #{opts.fetch(:host)}:#{opts.fetch(:port)} (#{e})")
      else
        begin
          yield server
        ensure
          server.close
        end
      end

      def parse(args)
        opts = {port: 0, host: "127.0.0.1"} #: Hash[Symbol, untyped]
        build_parser do |o|
          o.on("--port N", Integer) { |v| opts[:port] = v }
          o.on("--host HOST") { |v| opts[:host] = v }
        end.parse(args)
        opts
      end

      def announce(stdout, server, dir)
        port = server.addr.fetch(1)
        host = url_host(server.addr.fetch(3))
        stdout.puts("simplecov serve: serving #{dir} at http://#{host}:#{port}/")
        stdout.puts("Press Ctrl-C to stop.")
      end

      # IPv6 literals need brackets in a URL: `--host ::1` must announce
      # http://[::1]:PORT/, not the invalid http://::1:PORT/.
      def url_host(host)
        host.include?(":") ? "[#{host}]" : host
      end

      # One thread per connection: browsers open speculative sockets that send no
      # bytes, and a serial loop would stall every real request behind them.
      def serve_loop(server, dir, stdout)
        loop do
          Thread.new(server.accept) { |client| StaticFileHandler.handle_connection(client, dir) }
        end
      rescue Interrupt
        stdout.puts("\nsimplecov serve: stopping")
      end
    end
  end
end

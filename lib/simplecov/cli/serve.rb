# frozen_string_literal: true

require "optparse"
require_relative "command_helpers"
require_relative "serve/report_preparer"
require_relative "serve/static_file_handler"

module SimpleCov
  module CLI
    # `simplecov serve [--port N] [--host HOST]` — serve the coverage
    # report over HTTP. A small static file server backed by stdlib
    # `socket`, so there's no extra dependency just for "view a local
    # report on a CI box where `file://` doesn't work." This module is
    # the CLI wiring (options, binding, the accept loop); the HTTP
    # mechanics live in StaticFileHandler.
    module Serve
      extend CommandHelpers

    module_function

      def run(args, stdout:, stderr:, **)
        opts = parse(args)
        dir = SimpleCov::CLI.coverage_dir
        message = ReportPreparer.call(dir)
        return error(stderr, message) if message

        require "socket"
        with_server(opts, stderr) do |server|
          announce(stdout, server, dir)
          serve_loop(server, dir, stdout)
          0
        end
      end

      # Returns the block's exit status, or 1 when the socket can't be
      # bound (port already taken, privileged port, unresolvable host).
      def with_server(opts, stderr)
        # The receiver cast works around an rbs stdlib gap: TCPSocket's
        # explicit `self.new` shadows TCPServer#initialize's (host, port) form.
        server = (_ = TCPServer).new(opts[:host], opts[:port]) #: TCPServer
      rescue SystemCallError, SocketError => e
        error(stderr, "cannot bind to #{opts[:host]}:#{opts[:port]} (#{e.message})")
      else
        begin
          yield server
        ensure
          server.close
        end
      end

      def parse(args)
        opts = {port: 0, host: "127.0.0.1"} #: Hash[Symbol, untyped]
        OptionParser.new do |o|
          o.on("--port N", Integer) { |v| opts[:port] = v }
          o.on("--host HOST")       { |v| opts[:host] = v }
          on_help(o)
        end.parse(args)
        opts
      end

      def announce(stdout, server, dir)
        port = server.addr[1]
        host = url_host(server.addr[3])
        stdout.puts("simplecov serve: serving #{dir} at http://#{host}:#{port}/")
        stdout.puts("Press Ctrl-C to stop.")
      end

      # IPv6 literals need brackets in a URL (--host ::1 must announce
      # http://[::1]:PORT/, not the invalid http://::1:PORT/).
      def url_host(host)
        host.include?(":") ? "[#{host}]" : host
      end

      # One thread per connection: browsers open speculative sockets
      # that send no bytes, and a serial loop would stall every real
      # request (the report's assets included) behind them.
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

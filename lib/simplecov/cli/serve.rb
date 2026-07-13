# frozen_string_literal: true

require "optparse"

module SimpleCov
  module CLI
    # `simplecov serve [--port N] [--host HOST]` — serve the coverage
    # report over HTTP. A 30-line static file server backed by stdlib
    # `socket`, so there's no extra dependency just for "view a local
    # report on a CI box where `file://` doesn't work."
    module Serve
      MIME = {
        ".html" => "text/html; charset=utf-8",
        ".htm" => "text/html; charset=utf-8",
        ".css" => "text/css",
        ".js" => "application/javascript",
        ".json" => "application/json",
        ".svg" => "image/svg+xml",
        ".png" => "image/png",
        ".gif" => "image/gif",
        ".jpg" => "image/jpeg",
        ".jpeg" => "image/jpeg",
        ".ico" => "image/x-icon",
        ".txt" => "text/plain; charset=utf-8"
      }.freeze
      STATUS_TEXT = {
        200 => "OK", 400 => "Bad Request", 403 => "Forbidden",
        404 => "Not Found", 405 => "Method Not Allowed"
      }.freeze

    module_function

      def run(args, stdout:, stderr:, **)
        opts = parse(args)
        dir = SimpleCov::CLI.coverage_dir
        return error(stderr, "#{dir} doesn't exist; run your test suite first") unless File.directory?(dir)

        require "socket"
        with_server(opts) do |server|
          announce(stdout, server, dir)
          serve_loop(server, dir, stdout)
          0
        end
      end

      def with_server(opts)
        # The receiver cast works around an rbs stdlib gap: TCPSocket's
        # explicit `self.new` shadows TCPServer#initialize's (host, port) form.
        server = (_ = TCPServer).new(opts[:host], opts[:port]) #: TCPServer
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
        end.parse(args)
        opts
      end

      def announce(stdout, server, dir)
        port = server.addr[1]
        host = server.addr[3]
        stdout.puts("simplecov serve: serving #{dir} at http://#{host}:#{port}/")
        stdout.puts("Press Ctrl-C to stop.")
      end

      def serve_loop(server, dir, stdout)
        loop { handle_connection(server.accept, dir) }
      rescue Interrupt
        stdout.puts("\nsimplecov serve: stopping")
      end

      # Reads one HTTP request line, drains headers, serves the file or
      # writes a status response. Wide rescue so a misbehaving client
      # can't crash the server.
      def handle_connection(client, root)
        method, path = client.readline.split
        drain_headers(client)
        return respond(client, 405) unless method == "GET"

        file = resolve(path, root)
        return respond(client, file == :forbidden ? 403 : 404) unless file.is_a?(String)

        respond(client, 200, File.binread(file), MIME[File.extname(file).downcase])
      rescue StandardError
        # Misbehaving clients (truncated requests, connection resets,
        # invalid encoding) shouldn't take the whole server down.
        nil
      ensure
        # simplecov:disable — `client` is the parameter, never nil here;
        # the `&.` is purely defensive in case of future refactors
        client&.close
        # simplecov:enable
      end

      def drain_headers(client)
        loop { break if client.readline.strip.empty? }
      end

      # Returns the absolute path of the file to serve, :forbidden for
      # a traversal attempt (including symlinks that escape root), or
      # nil for "not found".
      def resolve(request_path, root)
        path = request_path.split("?", 2).first.to_s.sub(%r{^/}, "")
        absolute_root = File.realpath(root)
        candidate = File.expand_path(path.empty? ? "index.html" : path, absolute_root)
        # Reject `..` traversal and absolute-path attempts before
        # touching disk so they're 403, not 404.
        return :forbidden unless inside?(candidate, absolute_root)

        candidate = File.join(candidate, "index.html") if File.directory?(candidate)
        return nil unless File.file?(candidate)

        # Resolve symlinks last and re-check: a file inside root could
        # be a symlink pointing outside (e.g. /etc/passwd).
        real = File.realpath(candidate)
        inside?(real, absolute_root) ? real : :forbidden
      rescue Errno::ENOENT
        # simplecov:disable — TOCTOU: candidate vanished between
        # File.file? and File.realpath. Treat as "not found".
        nil
        # simplecov:enable
      end

      def inside?(path, root)
        path == root || path.start_with?(root + File::SEPARATOR)
      end

      def respond(client, status, body = "", content_type = "text/plain")
        client.write("HTTP/1.1 #{status} #{STATUS_TEXT[status] || 'Error'}\r\n",
                     "Content-Type: #{content_type || 'application/octet-stream'}\r\n",
                     "Content-Length: #{body.bytesize}\r\n",
                     "Connection: close\r\n\r\n")
        client.write(body)
      end

      def error(stderr, message)
        stderr.puts("simplecov serve: #{message}")
        1
      end
    end
  end
end

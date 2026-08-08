# frozen_string_literal: true

module SimpleCov
  module CLI
    module Serve
      # The HTTP mechanics behind `simplecov serve`: reads one request
      # per connection and answers it from the report directory, with
      # traversal-safe path resolution. Kept apart from the CLI wiring
      # (option parsing, binding, the accept loop) in serve.rb.
      module StaticFileHandler
        MIME = {
          ".html" => "text/html; charset=utf-8", ".htm" => "text/html; charset=utf-8",
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
        STATUS_TEXT = {200 => "OK", 400 => "Bad Request", 403 => "Forbidden",
                       404 => "Not Found", 405 => "Method Not Allowed"}.freeze

        # Seconds a connection may sit idle mid-request before its reads
        # raise IO::TimeoutError and the connection is dropped.
        READ_TIMEOUT = 5

      module_function

        # Reads one HTTP request line, drains headers, serves the file or
        # writes a status response. Wide rescue so a misbehaving client
        # can't crash the server. The read timeout keeps idle connections
        # from pinning their threads forever.
        def handle_connection(client, root)
          client.timeout = READ_TIMEOUT
          method, path = client.readline.split
          drain_headers(client)
          return respond(client, 405) unless method == "GET"

          serve_file(client, path, root)
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

        def serve_file(client, path, root)
          file = resolve(path, root)
          return respond(client, file == :forbidden ? 403 : 404) unless file.is_a?(String)

          respond(client, 200, File.binread(file), MIME[File.extname(file).downcase])
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
      end
    end
  end
end

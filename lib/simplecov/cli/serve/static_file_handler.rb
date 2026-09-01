# frozen_string_literal: true

module SimpleCov
  module CLI
    module Serve
      # The HTTP mechanics behind `simplecov serve`: reads one request per
      # connection and answers it from the report directory, with
      # traversal-safe path resolution. Kept apart from the CLI wiring in
      # serve.rb.
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

        # Seconds a connection may sit idle mid-request before its reads raise
        # IO::TimeoutError and the connection is dropped.
        READ_TIMEOUT = 5

        extend self

        # Reads one HTTP request line, drains headers, serves the file or writes a
        # status response. Wide rescue so a misbehaving client can't crash the
        # server.
        #
        # `routes` maps exact request paths (query string excluded) to callables
        # that take over the connection, the seam `simplecov watch` mounts its
        # /events stream on. A route may hold the socket for as long as it
        # likes; the ensure below closes it when the route returns.
        def handle_connection(client, root, routes = {})
          # JRuby doesn't implement IO#timeout=. Without the guard the
          # NoMethodError lands in the wide rescue below and every connection
          # closes with an empty response. An idle connection then pins its
          # thread instead of timing out, which only leaks a thread in an
          # interactive dev server.
          client.timeout = READ_TIMEOUT if client.respond_to?(:timeout=)
          method, path = client.readline.split
          drain_headers(client)
          # A request line without both tokens used to raise on `path.split` inside
          # the wide rescue, closing the connection with an empty response
          # instead of the 400 below.
          return respond(client, 400) if path.nil?

          dispatch(client, method, path, root, routes)
        rescue
          # Misbehaving clients (truncated requests, connection resets, invalid
          # encoding) shouldn't take the whole server down.
          nil
        ensure
          client.close
        end

        def dispatch(client, method, path, root, routes)
          return respond(client, 405) unless method.eql?("GET")

          route = routes[path.split("?").first]
          return route.call(client) if route

          serve_file(client, path, root)
        end

        def serve_file(client, path, root)
          file = resolve(path, root)
          # `resolve` answers a path, nothing for a file that is not there, or the
          # refusal itself.
          return respond(client, file ? 403 : 404) unless file.instance_of?(String)

          respond(client, 200, File.binread(file), MIME[File.extname(file).downcase])
        end

        def drain_headers(client)
          loop { break if client.readline.rstrip.empty? }
        end

        # Answers the absolute path of the file to serve, :forbidden for a
        # traversal attempt (symlinks that escape root included), or nil for
        # "not found".
        #
        # The request path is deliberately NOT percent-decoded: filenames needing
        # escapes don't occur in generated reports, and keeping `%2e%2e%2f` as
        # literal bytes is part of the traversal defense. If decoding is ever
        # added, it must happen BEFORE the `inside?` check.
        def resolve(request_path, root)
          path = request_path.split("?").first.to_s.delete_prefix("/")
          absolute_root = File.realpath(root)
          candidate = File.expand_path(path, absolute_root)
          # Rejected before touching disk, so traversal and absolute-path attempts
          # are 403, not 404.
          return :forbidden unless inside?(candidate, absolute_root)

          candidate = File.join(candidate, "index.html") if File.directory?(candidate)
          return nil unless File.file?(candidate)

          # Symlinks are resolved last and re-checked: a file inside root could be
          # a symlink pointing outside.
          real = File.realpath(candidate)
          inside?(real, absolute_root) ? real : :forbidden
        rescue Errno::ENOENT
          # TOCTOU: candidate vanished between File.file? and File.realpath.
          nil
        end

        def inside?(path, root)
          path.eql?(root) || path.start_with?(root + File::SEPARATOR)
        end

        def respond(client, status, body = "", content_type = "text/plain")
          client.write("HTTP/1.1 #{status} #{STATUS_TEXT[status] || "Error"}\r\n",
            "Content-Type: #{content_type || "application/octet-stream"}\r\n",
            "Content-Length: #{body.bytesize}\r\n",
            "Connection: close\r\n\r\n")
          client.write(body)
        end
      end
    end
  end
end

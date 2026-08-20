# frozen_string_literal: true

module SimpleCov
  module CLI
    module Watch
      # The live half of the watch server: an /events endpoint streaming
      # server-sent events to every open report tab, and an index route
      # that appends the reload listener to the artifact on the way out,
      # so the report on disk stays byte-identical to a plain run's.
      class LiveReport
        RELOAD_SCRIPT = "\n<script>new EventSource('/events').onmessage = () => location.reload();</script>\n"

        def initialize(dir)
          @dir = dir
          @queues = [] #: Array[Thread::Queue]
          @lock = Mutex.new
        end

        # Mounted into StaticFileHandler's route seam; every other path
        # keeps being served from the report directory unchanged.
        def routes
          page = method(:page)
          {"/events" => method(:stream), "/" => page, "/index.html" => page}
        end

        def broadcast(event = "reload")
          @lock.synchronize { @queues.each { |queue| queue << event } }
        end

        # Holds the connection open, forwarding each broadcast as one SSE
        # message, until the tab goes away and the write fails. A closed
        # tab that never sees another broadcast parks its thread on the
        # queue — a leak the dev-server trade accepts, like serve's own
        # engines-without-IO#timeout note.
        def stream(client)
          queue = Queue.new #: Thread::Queue
          begin
            @lock.synchronize { @queues << queue }
            forward(client, queue)
          ensure
            @lock.synchronize { @queues.delete(queue) }
          end
        end

        def forward(client, queue)
          client.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n" \
                       "Cache-Control: no-cache\r\n\r\n")
          loop { client.write("data: #{queue.pop}\n\n") }
        rescue IOError, SystemCallError
          nil
        end

        def page(client)
          body = File.binread(File.join(@dir, "index.html")) + RELOAD_SCRIPT
          Serve::StaticFileHandler.respond(client, 200, body, "text/html; charset=utf-8")
        rescue SystemCallError
          Serve::StaticFileHandler.respond(client, 404)
        end
      end
    end
  end
end

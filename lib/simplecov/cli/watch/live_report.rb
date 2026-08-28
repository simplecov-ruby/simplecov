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
          with_queues { |queues| queues.each { |queue| queue << event } }
        end

      private

        # Holds the connection open, forwarding each broadcast as one SSE
        # message, until the tab goes away and the write fails. A closed
        # tab that never sees another broadcast parks its thread on the
        # queue — a leak the dev-server trade accepts, like serve's own
        # engines-without-IO#timeout note.
        def stream(client)
          queue = Queue.new #: Thread::Queue
          begin
            with_queues { |queues| queues << queue }
            forward(client, queue)
          ensure
            with_queues { |queues| queues.delete(queue) }
          end
        end

        def forward(client, queue)
          client.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n" \
                       "Cache-Control: no-cache\r\n\r\n")
          loop { client.write("data: #{next_event(queue)}\n\n") }
        rescue IOError, SystemCallError
          nil
        end

        # The next broadcast, waiting on the queue until one arrives.
        #
        # `Thread::Queue#shift` is an alias of `#pop`, one method under
        # two names, so narrowing to it is a difference no example can
        # show. It is disabled here rather than pinned by a test.
        # mutant:disable
        def next_event(queue)
          queue.pop
        end

        def page(client)
          body = File.binread(File.join(@dir, "index.html")) + RELOAD_SCRIPT
          Serve::StaticFileHandler.respond(client, 200, body, "text/html; charset=utf-8")
        rescue SystemCallError
          Serve::StaticFileHandler.respond(client, 404)
        end

        # Every touch of the queue registry goes through the lock: an
        # accept thread adds and drops its own queue while the session
        # thread walks them all. The lock is the one thing here no test
        # can hold to account, because dropping it leaves a race rather
        # than a wrong answer.
        # mutant:disable
        def with_queues
          @lock.synchronize { yield @queues }
        end
      end
    end
  end
end

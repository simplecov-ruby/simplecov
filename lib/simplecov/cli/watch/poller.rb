# frozen_string_literal: true

module SimpleCov
  module CLI
    module Watch
      # Watches a fixed set of paths by polling mtimes, the trade chosen over a
      # filesystem-event dependency for a command that is optional to begin with.
      # Editors that save through a temporary file plus rename still move the final
      # path's mtime, which is all this looks at.
      class Poller
        def initialize
          @snapshot = {} #: Hash[String, untyped]
        end

        # Replaces the watched set, snapshotting current mtimes. A path with no file
        # snapshots as nil, so appearing counts as a change.
        def watch(paths)
          @snapshot = paths.to_h { |path| [path, stamp(path)] }
        end

        def size
          @snapshot.size
        end

        def changes
          changed = [] #: Array[String]
          @snapshot.each_key do |path|
            now = stamp(path)
            next if now.eql?(@snapshot.fetch(path))

            @snapshot[path] = now
            changed << path
          end
          changed
        end

        def stamp(path)
          File.mtime(path)
        rescue SystemCallError
          nil
        end
      end
    end
  end
end

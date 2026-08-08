# frozen_string_literal: true

module SimpleCov
  module ResultMerger
    # Run/worker metadata queries used by resultset storage and parallel
    # coordination. Kept separate from the coverage-folding implementation.
    module ResultsetRunIdentity
      # One namespaced identity per distinct worker that wrote to the
      # current run: `[:worker, id]` for entries that carry a worker id,
      # `[:legacy, command_name]` for fresh entries written without one
      # (an old SimpleCov writing to the same resultset). Pairs rather
      # than mangled strings, so a resultset mixing both kinds can never
      # alias a real worker id to a synthesized legacy identity.
      def worker_identities_for_run(results, run_id, started_at)
        results.filter_map do |command_name, data|
          next unless current_run_entry?(data, run_id, started_at)

          worker_id = data["worker_id"]
          worker_id.to_s.empty? ? [:legacy, command_name] : [:worker, worker_id.to_s]
        end.uniq
      end

      def current_run_entry?(entry, run_id, started_at)
        return false unless entry.is_a?(Hash)

        entry_run_id = entry["run_id"]
        return fresh_entry?(entry, started_at) unless entry_run_id
        return false unless run_id && entry_run_id == run_id
        return true if SimpleCov::RunIdentity.authoritative?

        fresh_entry?(entry, started_at)
      end

      def fresh_entry?(entry, started_at)
        timestamp = entry["timestamp"]
        timestamp.is_a?(Numeric) && started_at && timestamp >= started_at.to_f
      end

      # Whether `entry` was written by a runner concurrent with this
      # process: either it shares our run id (`current_run_entry?`), or it
      # was written strictly after our process started. A mismatched run
      # id must not defeat the timestamp check — a subprocess we shelled
      # out to (fork+exec) generates its own random run id, and its
      # freshly written entry is exactly the data issue #581 protects
      # from being clobbered. Strict id matching is reserved for worker
      # counting (`worker_identities_for_run`), where admitting a stale
      # entry would end a sibling wait early.
      def concurrent_runner_entry?(entry, incoming = nil)
        return false unless entry.is_a?(Hash)

        incoming_run_id = incoming["run_id"] if incoming.is_a?(Hash)
        started_at = SimpleCov.process_start_time
        return true if current_run_entry?(entry, incoming_run_id, started_at)

        written_after_start?(entry, started_at)
      end

      # Strictly after, unlike `fresh_entry?`: an entry stamped at the
      # exact instant we started is treated as leftover from a previous
      # run, so a same-second stale entry is still overwritten.
      def written_after_start?(entry, started_at)
        timestamp = entry["timestamp"]
        timestamp.is_a?(Numeric) && started_at && timestamp > started_at.to_f
      end
    end
  end
end

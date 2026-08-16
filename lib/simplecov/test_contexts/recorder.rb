# frozen_string_literal: true

require_relative "test_table"
require_relative "map"
require_relative "../useless_results_remover"

module SimpleCov
  module TestContexts
    # Attributes each test's executed lines by sampling
    # `Coverage.peek_result` before and after it. Lines executed between
    # tests land in no bitmap — the load-only signal. Snapshots are
    # filtered to the project root immediately; the snapshot callable
    # and root regex are injectable for tests.
    class Recorder
      DEFAULT_SNAPSHOT = -> { Coverage.peek_result }

      def initialize(snapshot: DEFAULT_SNAPSHOT, root_regex: UselessResultsRemover.root_regex)
        @snapshot = snapshot
        @root_regex = root_regex
        @table = TestTable.new
        @files = Hash.new { |files, path| files[path] = Hash.new(0) }
        @lock = Mutex.new
        @active = 0
        @poisoned = false
      end

      def poisoned?
        @poisoned
      end

      # Returns the block's value; the delta is captured in an ensure so
      # a raising or failing test is still attributed.
      def record(id, name = id)
        enter!
        before = nil #: snapshot_lines?
        begin
          before = poisoned? ? nil : snapshot_lines
          yield
        ensure
          settle(id, name, before)
        end
      end

      def to_map
        return nil if poisoned?

        Map.snapshot(@table, @files)
      end

    private

      # Rebalances the depth counter even when a snapshot raised, so a
      # stopped Coverage doesn't trip the overlap check for later tests.
      def settle(id, name, before)
        capture(id, name, before) if before && !poisoned?
      ensure
        leave!
      end

      def enter!
        @lock.synchronize do
          @active += 1
          poison! if @active > 1
        end
      end

      def leave!
        @lock.synchronize { @active -= 1 }
      end

      # Coverage's counters are process-global: concurrent tests cannot
      # be told apart, so shut off rather than misattribute.
      def poison!
        return if @poisoned

        @poisoned = true
        return unless SimpleCov.print_errors

        warn "[SimpleCov]: tests are running in parallel threads inside one process; " \
             "per-test contexts cannot be attributed and will not be recorded."
      end

      def capture(id, name, before)
        index = @table.intern(id, name)
        snapshot_lines.each do |path, after_lines|
          mask = delta_mask(before[path], after_lines)
          @files[path][index] |= mask unless mask.zero?
        end
      end

      # Builds the bitmap as a binary string so the arbitrary-precision
      # OR happens once per file rather than once per executed line.
      def delta_mask(before_lines, after_lines)
        return 0 if before_lines == after_lines

        bits = +"0"
        (after_lines.size - 1).downto(0) do |index|
          executed = after_lines[index].to_i > (before_lines ? before_lines[index].to_i : 0)
          bits << (executed ? "1" : "0")
        end
        Integer(bits, 2)
      end

      def snapshot_lines
        lines = {} #: snapshot_lines
        @snapshot.call.each do |path, data|
          next unless path.match?(@root_regex)

          # JRuby's Coverage reports a bare line array; CRuby a criteria hash.
          file_lines = data.is_a?(Hash) ? data[:lines] : data
          lines[path] = file_lines if file_lines
        end
        lines
      end
    end
  end
end

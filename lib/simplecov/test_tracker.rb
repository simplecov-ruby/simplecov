# frozen_string_literal: true

module SimpleCov
  #
  # Records each test as a context in a `ContextMap`. Enabled by the
  # `track_tests` configuration; installed into RSpec by
  # `SimpleCov.start_tracking` and into Minitest by the minitest plugin.
  # Any other runner can wrap its own units of work with
  # `SimpleCov.track_test`.
  #
  # The contract is `track(id) { }`: attribute the lines the block
  # executed to `id`, or abstain (`recorded_map` nil) — never guess. How
  # the lines are obtained is this class's private business, and today's
  # engine is a peek-diff: sample `Coverage.peek_result` around the block
  # and take the lines whose execution count grew (everything below
  # `enter` is that engine). If Ruby's Coverage ever grows native contexts
  # — a mode bit at `Coverage.setup` time and per-context executed-line
  # sets, the shape its C internals suggest — the engine is what gets
  # replaced, behind `Coverage.supported?(:contexts)`; the contract, the
  # `ContextMap`, and everything downstream stay.
  #
  # Two limits are the peek-diff engine's, not the contract's. It needs
  # per-line execution counts, which is why `track_tests` refuses to run
  # under `:oneshot_line` (a line reports only its first hit ever, so
  # every test after the first would show no delta). And tests overlapping
  # across threads cannot be told apart, because the counters being
  # diffed are process-global — a per-thread native engine could lift
  # that; this one abstains (see `enter`).
  #
  class TestTracker
    # The `ContextMap` accumulated so far.
    attr_reader :map

    def initialize(root_regex: UselessResultsRemover.root_regex)
      @map = ContextMap.new
      # Only files under the project root are attributed, judged by the
      # same regex the report's own universe is rooted with, case
      # tolerance included. A peek covers every file the process loaded —
      # every gem included — and diffing all of them on every test is the
      # cost that would make tracking unaffordable, for map entries
      # serialization would drop anyway.
      @root_regex = root_regex
      @lock = Mutex.new
      @owner = nil
      @depth = 0
      @poisoned = false
    end

    # Run the block and record the lines it executed as covered by
    # `test_id`. Returns the block's value. Records in an ensure block, so
    # a failing test still maps the lines it reached on the way down.
    def track(test_id)
      before = enter
      begin
        yield
      ensure
        settle(test_id, before)
      end
    end

    # Whether attribution has been given up on for this process (tests
    # overlapped across threads).
    def poisoned?
      @poisoned
    end

    # The map when its attribution is trustworthy, nil once poisoned.
    # This is what result-building stores: a poisoned recording must
    # vanish like one that never happened, so the merge's all-or-nothing
    # rule drops the run's map instead of keeping a wrong one.
    def recorded_map
      poisoned? ? nil : @map
    end

  private

    # Take the before-test snapshot, or nil when nothing may be recorded.
    # Same-thread reentrancy is fine — a line the inner test executed was
    # executed on the outer test's watch too, so attributing to both is
    # the truth — but a second thread means concurrent tests, and
    # `Coverage`'s counters are process-global: their deltas cannot be
    # told apart, so recording shuts off rather than misattribute.
    def enter
      @lock.synchronize do
        if @depth.zero?
          @owner = Thread.current
        elsif !@owner.equal?(Thread.current)
          poison
        end
        @depth += 1
      end
      @poisoned ? nil : Coverage.peek_result
    end

    # Record in any case `enter` allowed, unless the recording was
    # poisoned while this very test ran.
    def settle(test_id, before)
      @map.record(test_id, delta(before, Coverage.peek_result)) if before && !@poisoned
    ensure
      @lock.synchronize do
        @depth -= 1
        @owner = nil if @depth.zero?
      end
    end

    def poison
      return if @poisoned

      @poisoned = true
      return unless SimpleCov.print_errors

      warn "[SimpleCov]: tests are running concurrently in this process (parallel threads), " \
           "so per-test coverage cannot be attributed. Dropping this process's test map."
    end

    # The per-file bitmaps of lines whose count grew between the two peeks.
    # Files outside the root are skipped (see `initialize`); a file absent
    # from `before` was loaded by the test itself, so everything it
    # executed is the test's.
    def delta(before, after)
      changed = {} #: Hash[String, Integer]
      after.each do |path, file_coverage|
        next unless path.match?(@root_regex)

        bitmap = line_delta(lines_in(before[path]), lines_in(file_coverage))
        changed[path] = bitmap unless bitmap.zero?
      end
      changed
    end

    # A peek's per-file data is a criteria Hash when Coverage was started
    # with a criteria hash (how SimpleCov starts it) and a bare Array under
    # the older lines-only form (how someone else may have started it). No
    # lines at all — a branch-only or method-only start — means nothing to
    # diff.
    def lines_in(file_coverage)
      case file_coverage
      when Hash then file_coverage[:lines]
      when Array then file_coverage
      end
    end

    def line_delta(before_lines, after_lines)
      return 0 unless after_lines
      # The overwhelmingly common case: the test never entered this file.
      # Array equality is a fast C compare, the per-line loop is not.
      return 0 if before_lines == after_lines

      # Built as a binary string, highest line first, so the
      # arbitrary-precision math happens once per file rather than one
      # bignum OR per executed line. The leading zero keeps the parse
      # valid for an all-zero delta without changing any value.
      bits = +"0"
      (after_lines.size - 1).downto(0) do |index|
        bits << (grew?(after_lines[index], before_lines && before_lines[index]) ? "1" : "0")
      end
      Integer(bits, 2)
    end

    # A line belongs to the test when its count grew across the two peeks.
    # `previous` is nil both for a non-executable line (whose count is nil
    # too) and for a file the test itself loaded, where every executed
    # line is the test's.
    def grew?(count, previous)
      !count.nil? && count > (previous || 0)
    end
  end
end

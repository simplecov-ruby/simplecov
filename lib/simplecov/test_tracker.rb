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

    # The open segment: the context id everything since the last
    # boundary belongs to, and the peek that boundary took.
    Segment = Struct.new(:id, :opening)
    private_constant :Segment

    def initialize(root_regex: UselessResultsRemover.root_regex, granularity: :test)
      unless Configuration::TRACK_TESTS_GRANULARITIES.include?(granularity)
        raise ArgumentError, "unknown granularity #{granularity.inspect}, " \
                             "expected one of #{Configuration::TRACK_TESTS_GRANULARITIES.inspect}"
      end

      @map = ContextMap.new
      # Only files under the project root are attributed, judged by the
      # same regex the report's own universe is rooted with, case
      # tolerance included. A peek covers every file the process loaded —
      # every gem included — and diffing all of them on every test is the
      # cost that would make tracking unaffordable, for map entries
      # serialization would drop anyway.
      @delta = Delta.new(root_regex: root_regex)
      @granularity = granularity
      # The open segment and the thread that owns the current tracks are
      # left unset until there are any, which reads as nil.
      @lock = Mutex.new
      @depth = 0
      @poisoned = false
    end

    # Run the block and record the lines it executed as covered by
    # `test_id`'s context (the test itself at :test granularity, its file
    # at :file). Returns the block's value; a failing test's lines are
    # still attributed when its segment closes.
    def track(test_id)
      id = context_id(test_id)
      entry = enter(id)
      begin
        yield
      ensure
        settle(id, entry)
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
    # Flushes the open segment, so the answer carries every finished
    # track. At process exit `Coverage.result` has already stopped
    # measurement, so result-building passes the final coverage it just
    # took as the closing snapshot instead of peeking again.
    def recorded_map(closing: nil)
      return nil if poisoned?

      flush_segment(closing)
      @map
    end

  private

    # Returns the opening peek a nested track records against, and
    # nothing (nil) for an outermost track, whose segment machinery owns
    # its peeks, or when nothing may be recorded at all. Same-thread reentrancy is fine — a line
    # the inner test executed was executed on the outer test's watch too,
    # so attributing to both is the truth — but a second thread means
    # concurrent tests, and `Coverage`'s counters are process-global:
    # their deltas cannot be told apart, so recording shuts off rather
    # than misattribute.
    def enter(id)
      outermost = note_entry
      return nil if @poisoned
      return Coverage.peek_result unless outermost

      open_segment(id)
      nil
    end

    def note_entry
      @lock.synchronize do
        if @depth.zero?
          @owner = Thread.current
        elsif !@owner.equal?(Thread.current)
          poison
        end
        @depth += 1
        # Both are small Integers, so identity settles it.
        @depth.equal?(1)
      end
    end

    # A nested track records immediately against its own opening peek;
    # an outermost one leaves its segment open for the next boundary.
    # The owner needs no clearing here: the next track to find the depth
    # back at zero takes ownership itself.
    def settle(id, entry)
      @map.record(id, @delta.call(entry, Coverage.peek_result)) if entry && !@poisoned
    ensure
      @lock.synchronize { @depth -= 1 }
    end

    # Peeking is the dominant cost of tracking (the copy covers every
    # file the process loaded, branch and method tables included), so
    # recording settles at segment boundaries: consecutive tracks with
    # one context id share one open segment and pay nothing in between,
    # and a boundary's single peek closes one segment and opens the
    # next. In-root code that runs between two segments is attributed to
    # the later one, the documented price of the batching.
    def open_segment(id)
      return if @segment&.id.eql?(id)

      boundary = Coverage.peek_result
      close_segment(boundary)
      @segment = Segment.new(id, boundary)
    end

    def close_segment(closing)
      segment = @segment
      @map.record(segment.id, @delta.call(segment.opening, closing)) if segment
    end

    def flush_segment(closing)
      return unless @segment

      close_segment(closing || Coverage.peek_result)
      @segment = nil
    end

    # The identity a test contributes to: itself, or at :file granularity
    # its file, read by truncating the `path:line` id at the line number.
    # An id with no line tail (an exotic runner's fallback) stays whole.
    def context_id(test_id)
      return test_id unless @granularity.equal?(:file)

      path, sep, tail = test_id.rpartition(":")
      sep.empty? || !tail.match?(/\A\d+\z/) ? test_id : path
    end

    def poison
      return if @poisoned

      @poisoned = true
      return unless SimpleCov.print_errors

      warn "[SimpleCov]: tests are running concurrently in this process (parallel threads), " \
           "so per-test coverage cannot be attributed. Dropping this process's test map."
    end
  end
end

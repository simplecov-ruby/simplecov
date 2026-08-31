# frozen_string_literal: true

module SimpleCov
  #
  # Records each test as a context in a `ContextMap`. Enabled by the
  # `track_tests` configuration; installed into RSpec by
  # `SimpleCov.start_tracking` and into Minitest by the minitest plugin.
  # Any other runner can wrap its own units of work with
  # `SimpleCov.track_test`.
  #
  # The contract is `track(id) { }`: attribute the lines the block executed to
  # `id`, or abstain (`recorded_map` nil), never guess. How the lines are
  # obtained is this class's private business, and today's engine is a
  # peek-diff: sample `Coverage.peek_result` around the block and take the
  # lines whose execution count grew. If Ruby's Coverage ever grows native
  # contexts the engine is what gets replaced; the contract, the `ContextMap`,
  # and everything downstream stay.
  #
  # Two limits are the peek-diff engine's, not the contract's. It needs
  # per-line execution counts, which is why `track_tests` refuses to run under
  # `:oneshot_line`. And tests overlapping across threads cannot be told
  # apart, because the counters being diffed are process-global.
  #
  #
  class TestTracker
    attr_reader :map

    # The context id everything since the last boundary belongs to, and the
    # peek that boundary took.
    Segment = Struct.new(:id, :opening)
    private_constant :Segment

    def initialize(root_regex: UselessResultsRemover.root_regex, granularity: :test)
      unless Configuration::TRACK_TESTS_GRANULARITIES.include?(granularity)
        raise ArgumentError, "unknown granularity #{granularity.inspect}, " \
                             "expected one of #{Configuration::TRACK_TESTS_GRANULARITIES.inspect}"
      end

      @map = ContextMap.new
      # Only files under the project root are attributed, judged by the same
      # regex the report's own universe is rooted with. A peek covers every
      # file the process loaded, every gem included, and diffing all of them on
      # every test is the cost that would make tracking unaffordable.
      @delta = Delta.new(root_regex: root_regex)
      @granularity = granularity
      @lock = Mutex.new
      @depth = 0
      @poisoned = false
    end

    # Records the lines the block executed as covered by `test_id`'s context
    # (the test itself at :test granularity, its file at :file). A failing
    # test's lines are still attributed when its segment closes.
    def track(test_id)
      id = context_id(test_id)
      nested_opening = begin_track(id)
      begin
        yield
      ensure
        settle(id, nested_opening)
      end
    end

    def poisoned?
      @poisoned
    end

    # nil once poisoned: a poisoned recording must vanish like one that never
    # happened, so the merge's all-or-nothing rule drops the run's map instead
    # of keeping a wrong one. Flushes the open segment, so the answer carries
    # every finished track. At process exit `Coverage.result` has already
    # stopped measurement, so result-building passes the final coverage it just
    # took as the closing snapshot instead of peeking again.
    def recorded_map(closing: nil)
      return nil if poisoned?

      flush_segment(closing)
      @map
    end

  private

    # Same-thread reentrancy is fine, since a line the inner test executed was
    # executed on the outer test's watch too, but a second thread means
    # concurrent tests and `Coverage`'s counters are process-global: their
    # deltas cannot be told apart, so recording shuts off rather than
    # misattribute.
    def begin_track(id)
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
        @depth.equal?(1)
      end
    end

    # A nested track records immediately against its own opening peek; an
    # outermost one leaves its segment open for the next boundary. The owner
    # needs no clearing: the next track to find the depth back at zero takes
    # ownership itself.
    def settle(id, nested_opening)
      @map.record(id, @delta.call(nested_opening, Coverage.peek_result)) if nested_opening && !@poisoned
    ensure
      @lock.synchronize { @depth -= 1 }
    end

    # Peeking is the dominant cost of tracking (the copy covers every file the
    # process loaded, branch and method tables included), so recording settles
    # at segment boundaries: consecutive tracks with one context id share one
    # open segment and pay nothing in between. In-root code that runs between
    # two segments is attributed to the later one, the documented price.
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

    # An id with no `:line` tail (an exotic runner's fallback) stays whole.
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

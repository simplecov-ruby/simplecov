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

    # The context id everything since the last boundary belongs to (nil for
    # code no test owns), the peek that boundary took, and whether it records
    # a test file loading rather than a test running.
    Segment = Struct.new(:id, :opening, :loading)
    private_constant :Segment

    # `defined_tests` answers every test the process defined, as pairs of its
    # id and a name telling it apart from other tests under that id.
    def initialize(root_regex: UselessResultsRemover.root_regex, granularity: :test,
      defined_tests: -> { TestTracker.defined_tests })
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
      @defined_tests = defined_tests
      @started = {} #: Hash[String, Set[String]]
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

    # Credits the test file that starts loading at `path` with what its
    # loading runs (`describe` bodies, shared examples, helpers called at
    # definition time) until the next boundary. Loading is not a test, so it is
    # ignored while one runs, and files it loads for the first time are left to
    # no test: when a spec file's `require "rails_helper"` boots the app, that
    # boot belongs to every test, not to the spec file that happened to come
    # first.
    def test_file_loading(path)
      return unless TEST_FILE_NAME.match?(File.basename(path))

      prefix = File.join(SimpleCov.root, "")
      open_outside_tests(path.delete_prefix(prefix)) if path.start_with?(prefix)
    end

    # Marks the end of loading, so suite-level setup (RSpec's `before(:suite)`)
    # is left to no test instead of the last test file loaded.
    def suite_starting
      open_outside_tests(nil)
    end

    # Credits the test file at `path` with its `before(:all)` hooks, which RSpec
    # runs outside any test, instead of the test that ran before them.
    def test_file_starting(path)
      open_outside_tests(path, loading: false)
    end

    # Notes a test starting, skipped ones included, under `name`, which tells
    # it apart from other tests sharing its id.
    def test_started(test_id, name)
      ids_of(test_id).each { |id| (@started[id] ||= Set.new) << name }
    end

    def poisoned?
      @poisoned
    end

    # Why this process recorded no map, for the report to say in place of
    # suggesting `track_tests`, which is already on.
    def dropped_reason
      "tests ran concurrently in threads, which per-test coverage cannot tell apart" if poisoned?
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
      mark_partial_contexts
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
    # two tracks goes to the earlier one, unless a framework hook marks a
    # boundary first.
    def open_segment(id, loading: false)
      return if same_segment?(id, loading)

      boundary = Coverage.peek_result
      close_segment(boundary)
      @segment = Segment.new(id, boundary, loading)
    end

    # With no segment open, everything so far already belongs to no test.
    def same_segment?(id, loading)
      segment = @segment
      return id.nil? unless segment

      segment.id.eql?(id) && segment.loading.equal?(loading)
    end

    # A nil id is code no test owns, whose segment records nothing, so only a
    # named one's `loading` matters.
    def open_outside_tests(id, loading: true)
      open_segment(id, loading: loading) if @depth.zero? && !@poisoned
    end

    def close_segment(closing)
      segment = @segment
      return unless segment

      id = segment.id
      @map.record(id, @delta.call(segment.opening, closing, loading: segment.loading)) if id
    end

    def flush_segment(closing)
      return unless @segment

      close_segment(closing || Coverage.peek_result)
      @segment = nil
    end

    # A context some of whose tests never started, in a run filtered down to
    # some of the tests sharing one id or one test file, holds only what the
    # started ones ran.
    def mark_partial_contexts
      defined = {} #: Hash[String, Set[String]]
      @defined_tests.call.each do |test_id, name|
        ids_of(test_id).each { |id| (defined[id] ||= Set.new) << name }
      end
      defined.each do |id, names|
        @map.mark_partial(id) if @map.include?(id) && !names.subset?(@started.fetch(id) { Set.new })
      end
    end

    # The test's own id and its file's, which holds the file's loading and
    # setup, and at file granularity the test too.
    def ids_of(test_id)
      [test_id, test_id.sub(TEST_ID_TAIL, "")]
    end

    # An id with no tail (an exotic runner's fallback) stays whole.
    def context_id(test_id)
      @granularity.equal?(:file) ? test_id.sub(TEST_ID_TAIL, "") : test_id
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

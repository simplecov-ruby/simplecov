# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::RunIdentity do
  around do |example|
    SimpleCov::ParallelAdapters.reset_current!
    example.run
  ensure
    SimpleCov::ParallelAdapters.reset_current!
  end

  it "honors an explicit run identity and trusts it outright" do
    with_env("SIMPLECOV_RUN_ID" => "ci-run-42") do
      expect(described_class.generate).to eq(["ci-run-42", true])
    end
  end

  it "trusts an explicit run identity that merely looks like an inferred one" do
    with_env("SIMPLECOV_RUN_ID" => "parallel-parent:99", "TEST_ENV_NUMBER" => "1") do
      expect(described_class.generate).to eq(["parallel-parent:99", true])
    end
  end

  it "derives a shared native identity from parallel_tests' pid file" do
    with_env("SIMPLECOV_RUN_ID" => nil, "PARALLEL_PID_FILE" => "/tmp/parallel_tests-pidfile-123") do
      expect(described_class.generate).to eq(["parallel-tests:parallel_tests-pidfile-123", true])
    end
  end

  it "uses the launcher process for an env-only parallel runner, marked weak" do
    with_env("SIMPLECOV_RUN_ID" => nil, "PARALLEL_PID_FILE" => nil, "TEST_ENV_NUMBER" => "1") do
      expect(described_class.generate).to eq(["parallel-parent:#{Process.ppid}", false])
    end
  end

  it "falls back to a random identity that needs no freshness check" do
    with_env("SIMPLECOV_RUN_ID" => nil, "PARALLEL_PID_FILE" => nil, "TEST_ENV_NUMBER" => nil) do
      id, authoritative = described_class.generate
      expect(id).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
      expect(authoritative).to be true
    end
  end

  it "memoizes the id and its provenance together" do
    with_env("SIMPLECOV_RUN_ID" => nil, "PARALLEL_PID_FILE" => nil, "TEST_ENV_NUMBER" => "2") do
      with_pristine_identity do
        expect(described_class.current).to eq("parallel-parent:#{Process.ppid}")
        expect(described_class.authoritative?).to be false
      end
    end
  end

  it "normalizes parallel_tests' empty first-worker number" do
    with_env("SIMPLECOV_WORKER_ID" => nil, "TEST_ENV_NUMBER" => "") do
      expect(described_class.worker_id).to eq("1")
    end
  end

  it "uses a nonempty parallel worker number verbatim" do
    with_env("SIMPLECOV_WORKER_ID" => nil, "TEST_ENV_NUMBER" => "3") do
      expect(described_class.worker_id).to eq("3")
    end
  end

  it "honors an explicit worker identity" do
    with_env("SIMPLECOV_WORKER_ID" => "shard-a") do
      expect(described_class.worker_id).to eq("shard-a")
    end
  end

  # Snapshot and restore the memoized identity so an example can exercise
  # `current` and `authoritative?` without changing SimpleCov.run_id for
  # the rest of this (coverage-reporting) process. The two ivars are only
  # ever written together in materialize_current, so @current stands in
  # for both when checking whether an identity is memoized.
  def with_pristine_identity
    saved = take_memoized_identity
    yield
  ensure
    restore_memoized_identity(saved)
  end

  def take_memoized_identity
    return unless described_class.instance_variable_defined?(:@current)

    [described_class.remove_instance_variable(:@current), described_class.remove_instance_variable(:@authoritative)]
  end

  def restore_memoized_identity(saved)
    if saved
      described_class.instance_variable_set(:@current, saved[0])
      described_class.instance_variable_set(:@authoritative, saved[1])
    elsif described_class.instance_variable_defined?(:@current)
      described_class.remove_instance_variable(:@current)
      described_class.remove_instance_variable(:@authoritative)
    end
  end
end

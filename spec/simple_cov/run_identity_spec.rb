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
      expect(described_class.generate).to match([/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, true])
    end
  end

  it "memoizes the id of an env-only parallel runner" do
    with_weak_identity { expect(described_class.current).to eq("parallel-parent:#{Process.ppid}") }
  end

  it "memoizes that id's provenance together with it" do
    with_weak_identity do
      described_class.current

      expect(described_class.authoritative?).to be false
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

  it "reads an empty run identity as no run identity" do
    with_env("SIMPLECOV_RUN_ID" => "", "PARALLEL_PID_FILE" => "pidfile-7") do
      expect(described_class.generate).to eq(["parallel-tests:pidfile-7", true])
    end
  end

  it "reads an empty pid file path as no pid file" do
    with_env("SIMPLECOV_RUN_ID" => nil, "PARALLEL_PID_FILE" => "") do
      expect(described_class.generate).to match([/\A\h{8}-\h{4}-/, true])
    end
  end

  it "reads an empty worker identity as no worker identity" do
    with_env("SIMPLECOV_WORKER_ID" => "", "TEST_ENV_NUMBER" => "5") do
      expect(described_class.worker_id).to eq("5")
    end
  end

  it "names the worker by its process when no runner numbered it" do
    with_env("SIMPLECOV_WORKER_ID" => nil, "TEST_ENV_NUMBER" => nil) do
      expect(described_class.worker_id).to eq(Process.pid.to_s)
    end
  end

  it "settles the worker identity on first asking" do
    with_pristine_worker_identity do
      with_env("TEST_ENV_NUMBER" => "3") { expect(described_class.current_worker_id).to eq("3") }
    end
  end

  it "memoizes the worker identity, so a later number does not move it" do
    with_pristine_worker_identity do
      with_env("TEST_ENV_NUMBER" => "3") { described_class.current_worker_id }

      with_env("TEST_ENV_NUMBER" => "9") { expect(described_class.current_worker_id).to eq("3") }
    end
  end

  it "settles the provenance on first asking" do
    with_explicit_identity { expect(described_class.authoritative?).to be(true) }
  end

  it "settles the id alongside the provenance" do
    with_explicit_identity do
      described_class.authoritative?

      expect(described_class.current).to eq("ci-run-42")
    end
  end

  it "settles the identity once" do
    with_pristine_identity do
      with_env("SIMPLECOV_RUN_ID" => "first") { described_class.current }
      with_env("SIMPLECOV_RUN_ID" => "second") { expect(described_class.current).to eq("first") }
    end
  end

  context "when prepare has run" do
    around do |example|
      with_pristine_identity { example.run }
    end

    before do
      SimpleCov::ParallelAdapters.reset_current!
      described_class.remove_instance_variable(:@current_worker_id) if
        described_class.instance_variable_defined?(:@current_worker_id)

      with_env("SIMPLECOV_RUN_ID" => "ci-run-42") { described_class.prepare }
    end

    it "settles the run identity" do
      expect(described_class.instance_variable_defined?(:@current)).to be(true)
    end

    it "settles the worker identity" do
      expect(described_class.instance_variable_defined?(:@current_worker_id)).to be(true)
    end

    it "settles the adapter" do
      expect(SimpleCov::ParallelAdapters.instance_variable_defined?(:@current)).to be(true)
    end
  end

  def with_weak_identity(&block)
    with_env("SIMPLECOV_RUN_ID" => nil, "PARALLEL_PID_FILE" => nil, "TEST_ENV_NUMBER" => "2") do
      with_pristine_identity(&block)
    end
  end

  def with_explicit_identity(&block)
    with_pristine_identity do
      with_env("SIMPLECOV_RUN_ID" => "ci-run-42", &block)
    end
  end

  def with_pristine_identity
    saved = take_memoized_identity
    yield
  ensure
    restore_memoized_identity(saved)
  end

  def with_pristine_worker_identity
    saved = described_class.instance_variable_defined?(:@current_worker_id) &&
      described_class.remove_instance_variable(:@current_worker_id)
    yield
  ensure
    described_class.remove_instance_variable(:@current_worker_id)
    described_class.instance_variable_set(:@current_worker_id, saved) if saved
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

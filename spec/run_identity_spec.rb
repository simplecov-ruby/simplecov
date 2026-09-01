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

  it "reads an empty run identity as no run identity" do
    with_env("SIMPLECOV_RUN_ID" => "", "PARALLEL_PID_FILE" => "pidfile-7") do
      expect(described_class.generate).to eq(["parallel-tests:pidfile-7", true])
    end
  end

  it "reads an empty pid file path as no pid file" do
    with_env("SIMPLECOV_RUN_ID" => nil, "PARALLEL_PID_FILE" => "") do
      id, authoritative = described_class.generate
      expect(id).to match(/\A\h{8}-\h{4}-/)
      expect(authoritative).to be(true)
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

  it "memoizes the worker identity" do
    saved = described_class.instance_variable_defined?(:@current_worker_id) &&
      described_class.remove_instance_variable(:@current_worker_id)

    with_env("TEST_ENV_NUMBER" => "3") { expect(described_class.current_worker_id).to eq("3") }
    with_env("TEST_ENV_NUMBER" => "9") { expect(described_class.current_worker_id).to eq("3") }
  ensure
    described_class.remove_instance_variable(:@current_worker_id)
    described_class.instance_variable_set(:@current_worker_id, saved) if saved
  end

  it "settles the provenance on first asking, alongside the id" do
    with_pristine_identity do
      with_env("SIMPLECOV_RUN_ID" => "ci-run-42") do
        expect(described_class.authoritative?).to be(true)
        expect(described_class.current).to eq("ci-run-42")
      end
    end
  end

  it "settles the identity once" do
    with_pristine_identity do
      with_env("SIMPLECOV_RUN_ID" => "first") { described_class.current }
      with_env("SIMPLECOV_RUN_ID" => "second") do
        expect(described_class.current).to eq("first")
      end
    end
  end

  it "settles the adapter, the run and the worker together" do
    with_pristine_identity do
      SimpleCov::ParallelAdapters.reset_current!
      described_class.remove_instance_variable(:@current_worker_id) if
        described_class.instance_variable_defined?(:@current_worker_id)

      with_env("SIMPLECOV_RUN_ID" => "ci-run-42") { described_class.prepare }

      expect(described_class.instance_variable_defined?(:@current)).to be(true)
      expect(described_class.instance_variable_defined?(:@current_worker_id)).to be(true)
      expect(SimpleCov::ParallelAdapters.instance_variable_defined?(:@current)).to be(true)
    end
  end

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

# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::CurrentRun do
  subject(:run) { described_class.new }

  it "begins with no identity" do
    expect(run).to have_attributes(pid: nil, process_start_time: nil)
  end

  it "begins with no result and no flags" do
    expect(run).to have_attributes(result?: false, collating_result?: false, forked_subprocess?: false)
  end

  describe "#result?" do
    it "is exactly false while no result was ever stored" do
      expect(run.result?).to be(false)
    end

    it "hands back the result once one is held" do
      result = instance_double(SimpleCov::Result)
      run.result = result

      expect(run.result?).to be(result)
    end

    it "is nil, not false, once a held result has been cleared" do
      run.result = nil

      expect(run.result?).to be_nil
    end
  end

  describe "#collating_result?" do
    it "is exactly false before any finalizer ran" do
      expect(run.collating_result?).to be(false)
    end

    it "is true while the collate finalizer holds the flag" do
      run.collating_result = true

      expect(run.collating_result?).to be(true)
    end

    it "is false once the finalizer puts it down" do
      run.collating_result = false

      expect(run.collating_result?).to be(false)
    end
  end

  describe "#forked_subprocess?" do
    it "is exactly false in a process that was never forked" do
      expect(run.forked_subprocess?).to be(false)
    end

    it "is true, exactly, once the fork hook marks the child" do
      run.mark_forked_subprocess!

      expect(run.forked_subprocess?).to be(true)
    end
  end

  describe "#subprocess_serial" do
    it "starts at zero, so a first run and a re-run name their workers alike" do
      expect(run.subprocess_serial).to eq(0)
    end

    it "hands back the next ordinal" do
      expect(Array.new(2) { run.next_subprocess_serial! }).to eq([1, 2])
    end

    it "keeps the ordinal it handed back" do
      2.times { run.next_subprocess_serial! }

      expect(run.subprocess_serial).to eq(2)
    end
  end

  describe "#successor" do
    context "when the run held a result, a flag and an identity" do
      let(:following) do
        run.result = instance_double(SimpleCov::Result)
        run.collating_result = true
        run.pid = 4242
        run.process_start_time = 99.5
        run.successor
      end

      it "begins with no result and no flags" do
        expect(following).to have_attributes(result?: false, collating_result?: false)
      end

      it "begins with no identity" do
        expect(following).to have_attributes(pid: nil, process_start_time: nil)
      end
    end

    it "carries the fork genealogy: a forked child stays forked" do
      run.mark_forked_subprocess!

      expect(run.successor.forked_subprocess?).to be(true)
    end

    it "does not invent a fork that never happened" do
      expect(run.successor.forked_subprocess?).to be(false)
    end

    it "keeps counting subprocess serials where this run left off" do
      run.next_subprocess_serial!
      run.next_subprocess_serial!

      expect(run.successor.next_subprocess_serial!).to eq(3)
    end

    it "carries an untouched serial as the same starting point" do
      expect(run.successor.subprocess_serial).to eq(0)
    end
  end

  it "records the pid it is given" do
    run.pid = 4242

    expect(run.pid).to eq(4242)
  end

  it "records the start time it is given" do
    run.process_start_time = 99.5

    expect(run.process_start_time).to eq(99.5)
  end
end

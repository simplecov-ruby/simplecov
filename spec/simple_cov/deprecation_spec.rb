# frozen_string_literal: true

require "helper"

describe SimpleCov::Deprecation do
  before { described_class.reset! }
  after { described_class.reset! }

  def deprecated_alias(message)
    described_class.warn(message)
  end

  describe ".mode" do
    it "defaults to warning the first time it is asked" do
      described_class.remove_instance_variable(:@mode) if
        described_class.instance_variable_defined?(:@mode)

      expect(described_class.mode).to eq(:warn)
    end

    it "answers the raising mode that was assigned" do
      described_class.mode = :raise

      expect(described_class.mode).to eq(:raise)
    end

    it "answers the warning mode that was assigned over it" do
      described_class.mode = :raise
      described_class.mode = :warn

      expect(described_class.mode).to eq(:warn)
    end

    it "refuses a mode that is neither" do
      expect { described_class.mode = :silence }.to raise_error(
        SimpleCov::ConfigurationError, "deprecations takes :warn or :raise, got :silence"
      )
    end

    it "refuses a mode that is not a symbol at all" do
      expect { described_class.mode = nil }.to raise_error(
        SimpleCov::ConfigurationError, "deprecations takes :warn or :raise, got nil"
      )
    end

    it "leaves the mode alone when it refused one" do
      described_class.mode = :raise
      suppress(SimpleCov::ConfigurationError) { described_class.mode = :silence }

      expect(described_class.mode).to eq(:raise)
    end
  end

  describe ".caller_location" do
    it "reads the first frame of the window it asked for" do
      allow(Kernel).to receive(:caller).with(3..3).and_return(["lib/user.rb:1:in 'block'", "lib/deeper.rb:9"])

      expect(described_class.send(:caller_location)).to eq("lib/user.rb:1:in 'block'")
    end

    it "answers nil when the stack is too shallow to carry one" do
      allow(Kernel).to receive(:caller).with(3..3).and_return(nil)

      expect(described_class.send(:caller_location)).to be_nil
    end
  end

  describe ".warn" do
    it "prefixes the line that called the deprecated alias" do
      stderr = capture_stderr { deprecated_alias("`SimpleCov.old` is deprecated.") }
      called_on = __LINE__ - 1

      expect(stderr).to start_with("#{__FILE__}:#{called_on}:")
    end

    it "tags the message" do
      stderr = capture_stderr { deprecated_alias("`SimpleCov.old` is deprecated.") }

      expect(stderr).to end_with("[DEPRECATION] `SimpleCov.old` is deprecated.\n")
    end

    it "emits a given location only once, no matter how many times it repeats" do
      stderr = capture_stderr do
        3.times { described_class.warn("repeated", location: "file.rb:1") }
      end

      expect(stderr.scan("[DEPRECATION]").size).to eq(1)
    end

    it "still warns separately for distinct locations" do
      stderr = capture_stderr do
        described_class.warn("a", location: "file.rb:1")
        described_class.warn("b", location: "file.rb:2")
      end

      expect(stderr.scan("[DEPRECATION]").size).to eq(2)
    end

    context "with the mode set to raise" do
      before { described_class.mode = :raise }

      it "raises instead of warning" do
        expect { deprecated_alias("`SimpleCov.old` is deprecated.") }
          .to raise_error(SimpleCov::ConfigurationError, /`SimpleCov\.old` is deprecated/)
      end

      it "raises every time, not once per location" do
        2.times do
          expect { described_class.warn("repeated", location: "file.rb:1") }
            .to raise_error(SimpleCov::ConfigurationError)
        end
      end

      it "writes nothing to stderr" do
        stderr = capture_stderr { suppress(SimpleCov::ConfigurationError) { deprecated_alias("old api") } }

        expect(stderr).to be_empty
      end
    end

    it "omits the prefix and dedups on the message when no location is available" do
      stderr = capture_stderr do
        2.times { described_class.warn("locationless", location: nil) }
      end

      expect(stderr).to eq("[DEPRECATION] locationless\n")
    end

    it "warns the first time a location is seen" do
      first = capture_stderr { described_class.warn("once", location: "file.rb:1") }

      expect(first).to include("[DEPRECATION]")
    end

    it "stays quiet the second time, without a reset!" do
      capture_stderr { described_class.warn("once", location: "file.rb:1") }
      second = capture_stderr { described_class.warn("once", location: "file.rb:1") }

      expect(second).to be_empty
    end

    it "warns again after reset!" do
      capture_stderr { described_class.warn("once", location: "file.rb:1") }
      described_class.reset!
      third = capture_stderr { described_class.warn("once", location: "file.rb:1") }

      expect(third).to include("[DEPRECATION]")
    end
  end

  describe ".emitted" do
    it "builds an empty set the first time it is asked" do
      described_class.remove_instance_variable(:@emitted) if
        described_class.instance_variable_defined?(:@emitted)

      expect(described_class.emitted).to eq(Set.new)
    end

    it "builds a set, so the same location added twice is held once" do
      described_class.emitted.add("a")
      described_class.emitted.add("a")

      expect(described_class.emitted).to eq(Set["a"])
    end

    it "answers the same set each time it is asked" do
      first = described_class.emitted
      expect(described_class.emitted).to be(first)
    end
  end

  describe ".reset!" do
    it "records the location it warned about, before any reset" do
      described_class.warn("once", location: "file.rb:1")

      expect(described_class.emitted).not_to be_empty
    end

    it "forgets what was already warned about" do
      described_class.warn("once", location: "file.rb:1")
      described_class.reset!

      expect(described_class.emitted).to eq(Set.new)
    end

    it "puts the mode back to warning" do
      described_class.mode = :raise
      described_class.reset!

      expect(described_class.mode).to eq(:warn)
    end

    it "leaves the mode set rather than unset" do
      described_class.mode = :raise
      described_class.reset!

      expect(described_class.instance_variable_get(:@mode)).to eq(:warn)
    end

    it "leaves an empty set behind rather than nothing" do
      described_class.warn("once", location: "file.rb:1")
      described_class.reset!

      expect(described_class.instance_variable_get(:@emitted)).to eq(Set.new)
    end
  end

  describe "what it keys the deduplication on" do
    def two_messages_at(location)
      capture_stderr do
        described_class.warn("first", location: location)
        described_class.warn("second", location: location)
      end
    end

    it "says the first message from a location" do
      expect(two_messages_at("file.rb:1")).to include("first")
    end

    it "collapses a later message from the same location" do
      expect(two_messages_at("file.rb:1")).not_to include("second")
    end

    it "keeps warning separately about each distinct message when there is no location" do
      expect(two_messages_at(nil)).to include("first").and include("second")
    end

    it "says a message with no location once, without a prefix" do
      stderr = capture_stderr do
        2.times { described_class.warn("no place", location: nil) }
      end

      expect(stderr).to eq("[DEPRECATION] no place\n")
    end
  end
end

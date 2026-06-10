# frozen_string_literal: true

require "helper"

describe SimpleCov::Deprecation do
  before { described_class.reset! }
  after { described_class.reset! }

  # Stand in for a one-level deprecated alias (track_files, add_filter, …):
  # the auto-detected location should point at this method's caller.
  def deprecated_alias(message)
    described_class.warn(message)
  end

  describe ".warn" do
    it "tags the message and prefixes the caller location" do
      stderr = capture_stderr { deprecated_alias("`SimpleCov.old` is deprecated.") }

      expect(stderr).to include("[DEPRECATION] `SimpleCov.old` is deprecated.")
      expect(stderr).to include("#{__FILE__}:")
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

    it "omits the prefix and dedups on the message when no location is available" do
      stderr = capture_stderr do
        2.times { described_class.warn("locationless", location: nil) }
      end

      expect(stderr).to eq("[DEPRECATION] locationless\n")
    end

    it "warns again after reset!" do
      first = capture_stderr { described_class.warn("once", location: "file.rb:1") }
      second_without_reset = capture_stderr { described_class.warn("once", location: "file.rb:1") }
      described_class.reset!
      third_after_reset = capture_stderr { described_class.warn("once", location: "file.rb:1") }

      expect(first).to include("[DEPRECATION]")
      expect(second_without_reset).to be_empty
      expect(third_after_reset).to include("[DEPRECATION]")
    end
  end
end

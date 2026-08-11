# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes do
  describe ".print_error" do
    it "writes the message to stderr" do
      expect(capture_stderr { described_class.print_error("boom") }).to eq("boom\n")
    end

    it "stays quiet when stderr was closed before at_exit (e.g. by rspec-conductor)" do
      allow($stderr).to receive(:puts).and_raise(IOError, "closed stream")

      expect { described_class.print_error("boom") }.not_to raise_error
    end
  end
end

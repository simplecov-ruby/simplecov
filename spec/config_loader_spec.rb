# frozen_string_literal: true

require "helper"

RSpec.describe "loading config" do
  context "without ENV[HOME]" do
    it "does not raise any errors" do
      home = ENV.delete("HOME")
      begin
        expect { load "simplecov/load_global_config.rb" }.not_to raise_error
      ensure
        ENV["HOME"] = home
      end
    end
  end

  # Some container/CI images set HOME to an empty string. That passed the
  # set-at-all guard, and `File.expand_path("~")` then raised
  # ArgumentError (non-absolute home) out of `require "simplecov"`.
  context "with ENV[HOME] set but empty" do
    it "does not raise any errors" do
      home = ENV.fetch("HOME", nil)
      ENV["HOME"] = ""
      begin
        expect { load "simplecov/load_global_config.rb" }.not_to raise_error
      ensure
        ENV["HOME"] = home
      end
    end
  end
end

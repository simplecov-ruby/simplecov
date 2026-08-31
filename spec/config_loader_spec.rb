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

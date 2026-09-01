# frozen_string_literal: true

require "helper"

RSpec.describe "loading config" do
  context "without ENV[HOME]" do
    it "does not raise any errors" do
      with_env(HOME: nil) do
        expect { load "simplecov/load_global_config.rb" }.not_to raise_error
      end
    end
  end

  context "with ENV[HOME] set but empty" do
    it "does not raise any errors" do
      with_env(HOME: "") do
        expect { load "simplecov/load_global_config.rb" }.not_to raise_error
      end
    end
  end
end

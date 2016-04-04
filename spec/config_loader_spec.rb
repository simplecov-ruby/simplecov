require "helper"

describe "loading config" do
  context "without ENV[HOME]" do
    before do
      @home = ENV.delete("HOME")
    end

    after do
      ENV["HOME"] = @home
    end

    it "shouldn't raise any errors" do
      expect { require "simplecov/defaults" }.not_to raise_error
    end
  end
end

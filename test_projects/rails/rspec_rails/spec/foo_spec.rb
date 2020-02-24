require "rails_helper"

RSpec.describe Foo do
  describe "#bar" do
    it "bars" do
      expect(subject.bar).to eq "bar"
    end
  end
end

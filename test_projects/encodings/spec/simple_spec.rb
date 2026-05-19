require_relative "spec_helper"

RSpec.describe Fun do
  it "call things" do
    expect(subject.🇯🇵).to eq "tada!"
  end
end

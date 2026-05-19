require_relative "spec_helper"

RSpec.describe Subprocesses do
  it "call things" do
    expect(subject.run).to be true
  end
end

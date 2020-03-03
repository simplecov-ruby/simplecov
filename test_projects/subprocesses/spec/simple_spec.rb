require_relative "spec_helper"

describe Subprocesses do
  it "call things" do
    expect(subject.run).to be true
  end
end

# frozen_string_literal: true

require "spec_helper"

describe C do
  it "guard" do
    expect(subject.guard(42)).to be_nil
  end
end

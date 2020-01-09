# frozen_string_literal: true

require "spec_helper"

describe A do
  it "foo" do
    expect(subject.foo).to eq :foo
  end

  it "cond" do
    expect(subject.cond(false)).to eq :no
  end
end

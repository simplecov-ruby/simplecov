# frozen_string_literal: true

require "spec_helper"

describe D do
  it "case 4" do
    expect(subject.case(4)).to eq :foo
  end

  it "case nil" do
    expect(subject.case(nil)).to eq :nope
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe Code do
  it "#foo returns :foo being passed 42" do
    expect(subject.foo(42)).to eq :foo
  end
end

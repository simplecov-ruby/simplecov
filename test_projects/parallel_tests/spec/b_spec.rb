# frozen_string_literal: true

require "spec_helper"

RSpec.describe B do
  it "bar" do
    expect(subject.bar).to eq :bar
  end
end

# frozen_string_literal: true

require "spec_helper"
require "monorepo/extra"

RSpec.describe Monorepo::Extra do
  describe "#identity" do
    it "returns the same string" do
      expect(described_class.new("foo").identity).to eq("foo")
    end
  end
end

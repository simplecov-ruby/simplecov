# frozen_string_literal: true

require "spec_helper"

RSpec.describe "forking" do
  it do
    Process.waitpid(Kernel.fork {})
  end
end

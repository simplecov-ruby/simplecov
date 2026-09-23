# frozen_string_literal: true

require "helper"
require "simplecov/cli"
require "support/affected_runner_examples"

RSpec.describe SimpleCov::CLI::Affected::SpawnedRunner do
  before { skip "Process.wait2 answers no status on JRuby on Windows" if JRUBY_ON_WINDOWS }

  it_behaves_like "a runner for the selection"
end

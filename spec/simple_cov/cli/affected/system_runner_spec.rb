# frozen_string_literal: true

require "helper"
require "simplecov/cli"
require "support/affected_runner_examples"

RSpec.describe SimpleCov::CLI::Affected::SystemRunner do
  it_behaves_like "a runner for the selection"

  it "names the runner it could not start" do
    skip "JRuby answers a missing runner with an exit status instead" if RUBY_ENGINE == "jruby"

    expect { described_class.call(%w[definitely-not-a-command-xyz --flag], Dir.pwd) }
      .to raise_error(Errno::ENOENT, /definitely-not-a-command-xyz\z/)
  end

  it "is what the selection runs through only on JRuby on Windows" do
    expect(SimpleCov::CLI::Affected::RUNNER.equal?(described_class)).to be(JRUBY_ON_WINDOWS)
  end
end

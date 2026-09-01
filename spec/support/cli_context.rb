# frozen_string_literal: true

require "stringio"

# The CLI surface is one class, but the slowest subcommands have spec files
# of their own under spec/simple_cov/cli/ so that no one parallel worker has
# to run all of them. This is the plumbing they share.
RSpec.shared_context "a CLI" do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  def run(*argv)
    described_class.run(argv, stdout: stdout, stderr: stderr)
  end

  def run!(*argv)
    ok!(run(*argv))
  end

  def ok!(status)
    exited!(0, status)
  end

  # Refuses any status but the one the example takes for granted, so an example
  # about what the run printed needs no second expectation for how it ended.
  def exited!(expected, status)
    return status if status == expected

    raise "expected exit #{expected}, got #{status}:\n#{stderr.string}"
  end
end

RSpec.shared_examples "a --no-color subcommand" do
  before { allow(SimpleCov::Color).to receive(:enabled?).and_return(true) }

  it "succeeds with --no-color, even with Color.enabled? on" do
    expect(run(*no_color_argv)).to eq(0)
  end

  it "still prints its report" do
    run(*no_color_argv)

    expect(stdout.string).not_to be_empty
  end

  it "skips colorization" do
    run(*no_color_argv)

    expect(stdout.string).not_to include("\e[")
  end
end

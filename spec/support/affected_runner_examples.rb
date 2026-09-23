# frozen_string_literal: true

RSpec.shared_examples "a runner for the selection" do
  let(:root) { File.realpath(Dir.mktmpdir("simplecov-affected-runner-")) }

  after { FileUtils.remove_entry(root) }

  it "starts the runner at the root" do
    written = File.join(root, "pwd.txt")
    described_class.call([RbConfig.ruby, "-e", "File.write('#{written}', Dir.pwd)"], root)

    expect(File.read(written)).to eq(root)
  end

  it "answers the runner's exit status" do
    expect(described_class.call([RbConfig.ruby, "-e", "exit 3"], root)).to eq(3)
  end

  it "answers zero for a runner that succeeds" do
    expect(described_class.call([RbConfig.ruby, "-e", "exit"], root)).to eq(0)
  end

  it "answers 1 for a runner killed by a signal" do
    skip "no signals on Windows" if Gem.win_platform?

    expect(described_class.call([RbConfig.ruby, "-e", "Process.kill(:KILL, Process.pid)"], root)).to eq(1)
  end

  # CRuby raises for a runner that is not there. JRuby starts it through a
  # shell that answers the shell's own code for it instead.
  it "fails a runner that is not there" do
    expect(missing_runner_status).to (RUBY_ENGINE == "jruby") ? eq(127).or(eq(126)) : eq(127)
  end

  def missing_runner_status
    described_class.call(["definitely-not-a-command-xyz"], root)
  rescue Errno::ENOENT
    127
  end
end

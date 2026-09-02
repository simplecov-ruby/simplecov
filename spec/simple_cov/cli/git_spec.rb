# frozen_string_literal: true

require "helper"
require "open3"
require "simplecov/cli"
require "support/git_fixture"
require "tmpdir"

RSpec.describe SimpleCov::CLI::Git, mutant_expression: "SimpleCov::CLI::Git*" do
  let(:tmp) { Dir.mktmpdir("simplecov-cli-git-spec-") }

  after { FileUtils.rm_rf(tmp) }

  def repo!(branch)
    GitFixture.init_repo(tmp, branch: branch)
    system("git", "-C", tmp, "commit", "-q", "--allow-empty", "-m", "init", exception: true)
  end

  describe ".capture" do
    context "when git complains" do
      let(:captured) { described_class.capture("rev-parse", "--nope") }

      before do
        allow(Open3).to receive(:capture3).and_return(
          ["", "  fatal: not a thing  \nhint: try something else\n",
            instance_double(Process::Status, success?: false)]
        )
      end

      it "answers the first line of the complaint, trimmed" do
        expect(captured[1]).to eq("fatal: not a thing")
      end

      it "answers an unsuccessful run" do
        expect(captured[2]).to be(false)
      end
    end

    context "when git cannot be spawned" do
      let(:captured) { described_class.capture("status") }

      before { allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, "git") }

      it "answers nothing said on stdout" do
        expect(captured[0]).to be_nil
      end

      it "carries the message" do
        expect(captured[1]).to include("git")
      end

      it "answers an unsuccessful run" do
        expect(captured[2]).to be(false)
      end
    end

    it "answers nothing said when git said nothing" do
      allow(Open3).to receive(:capture3).and_return(["out\n", "", instance_double(Process::Status, success?: true)])

      expect(described_class.capture("rev-parse", "HEAD")).to eq(["out\n", "", true])
    end
  end

  describe ".toplevel" do
    it "answers the working tree's root, without the newline git adds" do
      repo!("main")
      expect(Dir.chdir(tmp) { described_class.toplevel }).to eq(File.realpath(tmp))
    end

    it "answers nothing outside a working tree" do
      allow(described_class).to receive(:capture).and_return(["", "fatal: not a git repository", false])
      expect(described_class.toplevel).to be_nil
    end
  end

  describe ".default_base" do
    it "resolves the branch origin's HEAD points at" do
      repo!("trunk")
      system("git", "-C", tmp, "update-ref", "refs/remotes/origin/trunk", "HEAD", exception: true)
      system("git", "-C", tmp, "symbolic-ref", "refs/remotes/origin/HEAD",
        "refs/remotes/origin/trunk", exception: true)

      expect(Dir.chdir(tmp) { described_class.default_base }).to eq("trunk")
    end

    it "falls back to main when no origin HEAD is recorded" do
      repo!("main")
      expect(Dir.chdir(tmp) { described_class.default_base }).to eq("main")
    end
  end

  describe ".option_like_ref?" do
    it "flags a ref git would parse as an option" do
      expect(described_class.option_like_ref?("--output=x")).to be(true)
    end

    it "leaves a plain branch name alone" do
      expect(described_class.option_like_ref?("main")).to be(false)
    end
  end
end

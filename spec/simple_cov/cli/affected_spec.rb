# frozen_string_literal: true

require "helper"
require "open3"
require "simplecov/cli"
require "support/cli_context"
require "support/git_fixture"
require "tmpdir"

RSpec.describe SimpleCov::CLI do
  include_context "a CLI"

  describe "affected subcommand", mutant_expression: "SimpleCov::CLI::Affected*" do
    let(:fixture_files) do
      {
        "lib/result.rb" => "# original\n", "lib/quiet.rb" => "# original\n",
        "lib/odd.rb" => "# original\n", "lib/stale.rb" => "# original\n",
        "lib/plain.rb" => "# original\n", "toplevel_test.rb" => "# original\n",
        "lib/suffixless.rb" => "# original\n", "spec/no_suffix" => "# original\n",
        "lib/plain2.rb" => "# original\n", "spec/test_helper.rb" => "# original\n",
        "spec/result_spec.rb" => "# original\n", "spec/source_file_spec.rb" => "# original\n",
        "spec/helper.rb" => "# original\n", "Gemfile.lock" => "# original\n",
        ".gitignore" => "coverage.json\nout.txt\n"
      }
    end
    let(:tmp) { GitFixture.checkout(fixture_files) }
    let(:payload) do
      {
        "contexts" => [
          "spec/result_spec.rb:42",
          "spec/source_file_spec.rb:12",
          "OddTest#test_odd",
          "spec/ghost_spec.rb:7",
          "toplevel_test.rb:99",
          "spec/no_suffix:3"
        ],
        "coverage" => {
          File.join(tmp, "lib/result.rb") => {"lines" => [nil, 1, 2, 0], "contexts" => {"0" => "6", "1" => "4"}},
          File.join(tmp, "lib/quiet.rb") => {"lines" => [1, nil]},
          File.join(tmp, "lib/odd.rb") => {"lines" => [1], "contexts" => {"2" => "1"}},
          File.join(tmp, "lib/stale.rb") => {"lines" => [1], "contexts" => {"3" => "1"}},
          File.join(tmp, "lib/plain.rb") => {"lines" => [1], "contexts" => {"4" => "1"}},
          File.join(tmp, "lib/suffixless.rb") => {"lines" => [1], "contexts" => {"5" => "1"}},
          File.join(tmp, "lib/plain2.rb") => {"lines" => [1], "contexts" => {"4" => "1"}}
        }
      }
    end

    def json_path = File.join(tmp, "coverage.json")

    def out_path = File.join(tmp, "out.txt")

    def file!(path, content = "# original\n")
      full = File.join(tmp, path)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
    end

    def commit!(message)
      GitFixture.commit!(tmp, message)
    end

    def git_in_repo(*argv)
      system("git", "-C", tmp, *argv, exception: true)
    end

    before { File.write(json_path, JSON.dump(payload)) }

    after { FileUtils.rm_rf(tmp) }

    def run_in_repo(*argv)
      Dir.chdir(tmp) { run(*argv) }
    end

    def run_in_spec_dir(*argv)
      Dir.chdir(File.join(tmp, "spec")) { run(*argv) }
    end

    def missing_command_status
      return eq(127) unless RUBY_ENGINE == "jruby"

      eq(127).or eq(126)
    end

    context "with changed code recorded tests touch" do
      before do
        file!("lib/result.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "selects the test files whose recorded tests touch it" do
        expect(stdout.string).to eq("spec/result_spec.rb\nspec/source_file_spec.rb\n")
      end

      it "says nothing on stderr" do
        expect(stderr.string).to be_empty
      end
    end

    context "with a changed test file" do
      before do
        file!("spec/result_spec.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "always selects it" do
        expect(stdout.string).to eq("spec/result_spec.rb\n")
      end

      it "says nothing on stderr" do
        expect(stderr.string).to be_empty
      end
    end

    context "with a new test file the map has never seen" do
      before do
        file!("spec/brand_new_spec.rb")
        run_in_repo("affected", "--input", json_path)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "always selects it" do
        expect(stdout.string).to eq("spec/brand_new_spec.rb\n")
      end

      it "says nothing on stderr" do
        expect(stderr.string).to be_empty
      end
    end

    context "when no recorded test touches the change" do
      before do
        file!("lib/quiet.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "answers an empty selection" do
        expect(stdout.string).to be_empty
      end

      it "notes it on stderr" do
        expect(stderr.string).to eq("simplecov affected: no recorded test touches the changed code\n")
      end
    end

    context "when nothing differs from the base" do
      before { run_in_repo("affected", "--input", json_path) }

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "answers an empty selection" do
        expect(stdout.string).to be_empty
      end

      it "notes it on stderr" do
        expect(stderr.string).to eq("simplecov affected: no changes against main\n")
      end
    end

    context "with an origin HEAD pointing at another branch" do
      before do
        system("git", "-C", tmp, "branch", "-m", "main", "trunk", exception: true)
        system("git", "-C", tmp, "update-ref", "refs/remotes/origin/trunk", "HEAD", exception: true)
        system("git", "-C", tmp, "symbolic-ref", "refs/remotes/origin/HEAD",
          "refs/remotes/origin/trunk", exception: true)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "defaults the base to that branch" do
        run_in_repo("affected", "--input", json_path)

        expect(stderr.string).to eq("simplecov affected: no changes against trunk\n")
      end
    end

    it "succeeds under --json when nothing differs from the base" do
      expect(run_in_repo("affected", "--input", json_path, "--json")).to eq(0)
    end

    it "still emits a JSON object when nothing differs from the base" do
      run_in_repo("affected", "--input", json_path, "--json")

      expect(JSON.parse(stdout.string)).to eq("full_suite" => false, "triggers" => [], "tests" => [])
    end

    context "with a deleted test file the map never knew" do
      before do
        file!("spec/unrecorded_spec.rb")
        commit!("add unrecorded spec")
        File.delete(File.join(tmp, "spec/unrecorded_spec.rb"))
        run_in_repo("affected", "--input", json_path)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "drops it" do
        expect(stdout.string).to be_empty
      end

      it "says nothing about it beyond the usual note" do
        expect(stderr.string).to eq("simplecov affected: no recorded test touches the changed code\n")
      end
    end

    context "with --base" do
      before do
        file!("lib/result.rb", "# changed\n")
        commit!("change result")
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path, "--base", "HEAD~1")).to eq(0)
      end

      it "diffs against the ref it was given" do
        run_in_repo("affected", "--input", json_path, "--base", "HEAD~1")

        expect(stdout.string).to eq("spec/result_spec.rb\nspec/source_file_spec.rb\n")
      end
    end

    context "with commits that landed on the base after the branch point" do
      before do
        system("git", "-C", tmp, "switch", "-qc", "feature", exception: true)
        system("git", "-C", tmp, "switch", "-q", "main", exception: true)
        file!("lib/quiet.rb", "# changed on main\n")
        commit!("change quiet on main")
        system("git", "-C", tmp, "switch", "-q", "feature", exception: true)
        file!("lib/result.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "ignores them" do
        expect(stdout.string).to eq("spec/result_spec.rb\nspec/source_file_spec.rb\n")
      end

      it "says nothing on stderr" do
        expect(stderr.string).to be_empty
      end
    end

    context "when run from a subdirectory" do
      before do
        file!("lib/result.rb", "# changed\n")
        run_in_spec_dir("affected", "--input", json_path)
      end

      it "succeeds" do
        expect(run_in_spec_dir("affected", "--input", json_path)).to eq(0)
      end

      it "selects across the whole change" do
        expect(stdout.string).to eq("spec/result_spec.rb\nspec/source_file_spec.rb\n")
      end

      it "says nothing on stderr" do
        expect(stderr.string).to be_empty
      end
    end

    context "with a runner" do
      let(:script) { "File.write(#{out_path.inspect}, Dir.pwd)" }

      before { file!("lib/result.rb", "# changed\n") }

      it "succeeds" do
        expect(run_in_spec_dir("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", script)).to eq(0)
      end

      it "starts it at the repository root" do
        run_in_spec_dir("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", script)

        expect(File.read(out_path)).to eq(File.realpath(tmp))
      end
    end

    context "with a changed file the report knows only under another path" do
      before do
        payload["coverage"].delete(File.join(tmp, "lib/result.rb"))
        payload["coverage"]["/elsewhere/lib/result.rb"] = {"lines" => [1], "contexts" => {"0" => "1"}}
        File.write(json_path, JSON.dump(payload))
        file!("lib/result.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "resolves changed files exactly instead of by suffix" do
        expect(stdout.string).to be_empty
      end

      it "names the file it could not resolve" do
        expect(stderr.string).to include("lib/result.rb changed but")
      end

      it "falls back to the full suite" do
        expect(stderr.string).to include("falling back to the full suite")
      end
    end

    context "with a report keyed by relative paths" do
      before do
        payload["coverage"] = payload["coverage"].transform_keys { |key| key.delete_prefix("#{tmp}/") }
        File.write(json_path, JSON.dump(payload))
        file!("lib/result.rb", "# changed\n")
      end

      it "succeeds from a subdirectory" do
        expect(run_in_spec_dir("affected", "--input", json_path)).to eq(0)
      end

      it "resolves them from a subdirectory too" do
        run_in_spec_dir("affected", "--input", json_path)

        expect(stdout.string).to eq("spec/result_spec.rb\nspec/source_file_spec.rb\n")
      end
    end

    context "when run outside a git working tree" do
      def run_outside_a_repo
        Dir.mktmpdir("simplecov-cli-affected-plain-") do |plain|
          Dir.chdir(plain) { run("affected", "--input", json_path) }
        end
      end

      it "errors" do
        expect(run_outside_a_repo).to eq(1)
      end

      it "selects nothing" do
        run_outside_a_repo

        expect(stdout.string).to be_empty
      end

      it "says why" do
        run_outside_a_repo

        expect(stderr.string).to eq("simplecov affected: not inside a git working tree\n")
      end
    end

    context "with a report that carries no coverage" do
      before do
        payload.delete("coverage")
        File.write(json_path, JSON.dump(payload))
        file!("lib/result.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "says the report has no data for the change" do
        expect(stderr.string).to include("has no data for it")
      end

      it "falls back to the full suite" do
        expect(stderr.string).to include("falling back to the full suite")
      end
    end

    context "with a report whose coverage is the wrong shape" do
      before do
        payload["coverage"] = []
        File.write(json_path, JSON.dump(payload))
        file!("lib/result.rb", "# changed\n")
      end

      it "refuses it" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      end

      it "says what the section should have been" do
        run_in_repo("affected", "--input", json_path)

        expect(stderr.string).to eq(
          %(simplecov affected: input file #{json_path.inspect} isn't valid JSON ("coverage" must be an object)\n)
        )
      end
    end

    context "with a recorded test file at the repository root" do
      before do
        file!("lib/plain.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "selects it" do
        expect(stdout.string).to eq("toplevel_test.rb\n")
      end

      it "says nothing on stderr" do
        expect(stderr.string).to be_empty
      end
    end

    describe ".parse" do
      it "starts with no base, no runner, and both compact forms off" do
        expect(SimpleCov::CLI::Affected.parse([]))
          .to eq(input: described_class.default_input, json: false, no_color: false,
            base: nil, run: nil, rest: [])
      end

      it "splits the runner command off at --run" do
        opts = SimpleCov::CLI::Affected.parse(%w[--base main --run rake test --verbose])
        expect(opts).to include(base: "main", run: %w[rake test --verbose], rest: [])
      end

      it "leaves an empty runner command empty rather than absent" do
        expect(SimpleCov::CLI::Affected.parse(%w[--run])).to include(run: [])
      end

      it "answers a head and no runner when there is no --run" do
        expect(SimpleCov::CLI::Affected.split_runner(%w[--base main])).to eq([%w[--base main], nil])
      end

      it "answers the head and the runner when there is one" do
        expect(SimpleCov::CLI::Affected.split_runner(%w[--base main --run rake])).to eq([%w[--base main], %w[rake]])
      end
    end

    context "with more than one stray positional" do
      it "errors" do
        expect(run_in_repo("affected", "--input", json_path, "feature-x", "feature-y")).to eq(1)
      end

      it "names the first, not the last" do
        run_in_repo("affected", "--input", json_path, "feature-x", "feature-y")

        expect(stderr.string)
          .to eq(%(simplecov affected: unexpected argument "feature-x" (did you mean `--base feature-x`?)\n))
      end
    end

    context "with a missing input" do
      let(:missing) { File.join(tmp, "nope.json") }

      it "errors" do
        expect(run_in_repo("affected", "--input", missing)).to eq(1)
      end

      it "names itself and the file" do
        run_in_repo("affected", "--input", missing)

        expect(stderr.string).to eq("simplecov affected: #{missing} not found\n")
      end
    end

    context "with an input that is not JSON at all" do
      before { File.write(json_path, "not json") }

      it "errors" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      end

      it "says so" do
        run_in_repo("affected", "--input", json_path)

        expect(stderr.string).to start_with(%(simplecov affected: input file #{json_path.inspect} isn't valid JSON))
      end
    end

    context "with a recorded test file that carries no .rb suffix" do
      before do
        file!("lib/suffixless.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "selects it" do
        expect(stdout.string).to eq("spec/no_suffix\n")
      end

      it "says nothing on stderr" do
        expect(stderr.string).to be_empty
      end
    end

    context "with changes selecting the same test more than once" do
      before do
        file!("lib/plain.rb", "# changed\n")
        file!("lib/plain2.rb", "# changed\n")
        file!("lib/result.rb", "# changed\n")
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "names each selected test file once, in order" do
        run_in_repo("affected", "--input", json_path)

        expect(stdout.string).to eq("spec/result_spec.rb\nspec/source_file_spec.rb\ntoplevel_test.rb\n")
      end
    end

    context "when the whole suite runs" do
      let(:parsed) { JSON.parse(stdout.string) }

      before do
        file!("lib/result.rb", "# changed\n")
        file!("lib/stale.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path, "--json")
      end

      it "succeeds under --json" do
        expect(run_in_repo("affected", "--input", json_path, "--json")).to eq(0)
      end

      it "says so under --json" do
        expect(parsed["full_suite"]).to be true
      end

      it "emits no tests under --json" do
        expect(parsed["tests"]).to be_empty
      end
    end

    context "with a runner it cannot run for the full suite" do
      let(:missing) { File.join(tmp, "nope-does-not-exist") }

      before { file!("Gemfile.lock", "# changed\n") }

      it "answers the shell's own code" do
        expect(run_in_repo("affected", "--input", json_path, "--run", missing)).to missing_command_status
      end

      it "names the command", if: RUBY_ENGINE == "ruby" do
        run_in_repo("affected", "--input", json_path, "--run", missing)

        expect(stderr.string).to include("cannot run #{missing.inspect} (No such file or directory")
      end
    end

    context "with commits on both sides of the merge base" do
      before do
        git_in_repo("checkout", "-q", "-b", "feature")
        file!("lib/result.rb", "# changed\n")
        commit!("change on the branch")
        git_in_repo("checkout", "-q", "main")
        file!("lib/plain.rb", "# changed on main\n")
        commit!("change on main")
        git_in_repo("checkout", "-q", "feature")
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path, "--base", "main")).to eq(0)
      end

      it "diffs against the merge base, not the base's tip" do
        run_in_repo("affected", "--input", json_path, "--base", "main")

        expect(stdout.string).to eq("spec/result_spec.rb\nspec/source_file_spec.rb\n")
      end
    end

    context "with a base it cannot resolve" do
      it "errors" do
        expect(run_in_repo("affected", "--input", json_path, "--base", "no-such-ref")).to eq(1)
      end

      it "relays what git said" do
        run_in_repo("affected", "--input", json_path, "--base", "no-such-ref")

        expect(stderr.string).to start_with("simplecov affected: `git diff` failed: ")
      end

      it "says it in one line" do
        run_in_repo("affected", "--input", json_path, "--base", "no-such-ref")

        expect(stderr.string.lines.size).to eq(1)
      end
    end

    context "with a changed test file named like a test but placed like a helper" do
      before do
        file!("spec/test_helper.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "recognises it by its own name, not by its path" do
        expect(stdout.string).to eq("spec/test_helper.rb\n")
      end

      it "says nothing on stderr" do
        expect(stderr.string).to be_empty
      end
    end

    context "with a contexts table that indexes past the recorded tests" do
      before do
        payload["coverage"][File.join(tmp, "lib/result.rb")] = {"lines" => [1], "contexts" => {"7" => "1"}}
        File.write(json_path, JSON.dump(payload))
        file!("lib/result.rb", "# changed\n")
      end

      it "refuses it" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      end

      it "says what was malformed" do
        run_in_repo("affected", "--input", json_path)

        expect(stderr.string).to eq(
          "simplecov affected: input file #{json_path.inspect} isn't valid JSON " \
          "(entry for lib/result.rb carries a malformed \"contexts\" table)\n"
        )
      end
    end

    context "with a base ref that is also a path in the tree" do
      before do
        git_in_repo("branch", "lib/quiet.rb")
        git_in_repo("checkout", "-q", "-b", "feature")
        file!("lib/result.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path, "--base", "lib/quiet.rb")
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path, "--base", "lib/quiet.rb")).to eq(0)
      end

      it "diffs against the ref" do
        expect(stdout.string).to eq("spec/result_spec.rb\nspec/source_file_spec.rb\n")
      end

      it "says nothing on stderr" do
        expect(stderr.string).to be_empty
      end
    end

    context "with a file that is both changed and untracked" do
      before { git_in_repo("rm", "--cached", "-q", "Gemfile.lock") }

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "names it only once" do
        run_in_repo("affected", "--input", json_path)

        expect(stderr.string.scan("Gemfile.lock changed but").size).to eq(1)
      end
    end

    context "with a git that cannot run the diff" do
      before do
        allow(SimpleCov::CLI::Git).to receive(:capture).and_wrap_original do |original, *argv|
          argv.include?("diff") ? [nil, "No such file or directory", false] : original.call(*argv)
        end
        file!("lib/result.rb", "# changed\n")
      end

      it "errors" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      end

      it "reports it once" do
        run_in_repo("affected", "--input", json_path)

        expect(stderr.string).to eq("simplecov affected: cannot run git (No such file or directory)\n")
      end
    end

    context "with a git it cannot run at all" do
      before { allow(SimpleCov::CLI::Git).to receive(:capture).and_return([nil, "No such file or directory", false]) }

      it "errors" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      end

      it "reports it once" do
        run_in_repo("affected", "--input", json_path)

        expect(stderr.string).to eq("simplecov affected: cannot run git (No such file or directory)\n")
      end
    end

    context "with a stray positional that looks like a forgotten --base" do
      before { run_in_repo("affected", "--input", json_path, "feature-x") }

      it "rejects it" do
        expect(run_in_repo("affected", "--input", json_path, "feature-x")).to eq(1)
      end

      it "selects nothing" do
        expect(stdout.string).to be_empty
      end

      it "suggests the flag" do
        expect(stderr.string)
          .to eq(%(simplecov affected: unexpected argument "feature-x" (did you mean `--base feature-x`?)\n))
      end
    end

    context "with a base ref that would read as a git option" do
      before { run_in_repo("affected", "--input", json_path, "--base=--output=evil") }

      it "refuses it" do
        expect(run_in_repo("affected", "--input", json_path, "--base=--output=evil")).to eq(1)
      end

      it "selects nothing" do
        expect(stdout.string).to be_empty
      end

      it "says why" do
        expect(stderr.string).to eq(%(simplecov affected: invalid base ref "--output=evil"\n))
      end
    end

    context "with a changed file the report has no data for" do
      before do
        file!("Gemfile.lock", "# changed\n")
        file!("lib/result.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "selects nothing" do
        expect(stdout.string).to be_empty
      end

      it "names the file" do
        expect(stderr.string).to include("Gemfile.lock changed but #{json_path} has no data for it")
      end

      it "falls back to the full suite" do
        expect(stderr.string).to include("falling back to the full suite")
      end
    end

    context "with a changed spec helper" do
      before do
        file!("spec/helper.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "selects nothing" do
        expect(stdout.string).to be_empty
      end

      it "treats it as outside the tracked set" do
        expect(stderr.string).to include("spec/helper.rb changed but")
      end

      it "falls back to the full suite" do
        expect(stderr.string).to include("falling back to the full suite")
      end
    end

    context "with a recorded test that has no file location" do
      before do
        file!("lib/odd.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "selects nothing" do
        expect(stdout.string).to be_empty
      end

      it "names the test" do
        expect(stderr.string).to include(
          "simplecov affected: recorded test OddTest#test_odd touches lib/odd.rb but has no file location"
        )
      end

      it "falls back to the full suite" do
        expect(stderr.string).to include("falling back to the full suite")
      end
    end

    context "when the map names a test file that no longer exists" do
      before do
        file!("lib/stale.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "selects nothing" do
        expect(stdout.string).to be_empty
      end

      it "names the file" do
        expect(stderr.string)
          .to include("simplecov affected: recorded test file spec/ghost_spec.rb no longer exists")
      end

      it "falls back to the full suite" do
        expect(stderr.string).to include("falling back to the full suite")
      end
    end

    context "with a test file the change itself deleted" do
      before do
        File.delete(File.join(tmp, "spec/source_file_spec.rb"))
        file!("lib/result.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "drops it from the selection" do
        expect(stdout.string).to eq("spec/result_spec.rb\n")
      end

      it "says it skipped it" do
        expect(stderr.string).to include("skipping deleted test file spec/source_file_spec.rb")
      end

      it "does not fall back" do
        expect(stderr.string).not_to include("full suite")
      end
    end

    context "with a selection under --json" do
      before { file!("lib/result.rb", "# changed\n") }

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path, "--json")).to eq(0)
      end

      it "emits it as a JSON object" do
        run_in_repo("affected", "--input", json_path, "--json")

        expect(JSON.parse(stdout.string)).to eq(
          "full_suite" => false, "triggers" => [], "tests" => ["spec/result_spec.rb", "spec/source_file_spec.rb"]
        )
      end
    end

    context "with a fallback under --json" do
      let(:parsed) { JSON.parse(stdout.string) }

      before do
        file!("Gemfile.lock", "# changed\n")
        run_in_repo("affected", "--input", json_path, "--json")
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path, "--json")).to eq(0)
      end

      it "says the whole suite runs" do
        expect(parsed["full_suite"]).to be(true)
      end

      it "selects no tests" do
        expect(parsed["tests"]).to eq([])
      end

      it "carries the triggers" do
        expect(parsed["triggers"].join).to include("Gemfile.lock")
      end
    end

    context "with a selection under --run" do
      let(:script) { "File.write(#{out_path.inspect}, ARGV.join(' '))" }

      before do
        file!("lib/result.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", script)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", script)).to eq(0)
      end

      it "hands the selection to the runner" do
        expect(File.read(out_path)).to eq("spec/result_spec.rb spec/source_file_spec.rb")
      end

      it "counts the files it is running" do
        expect(stderr.string).to include("running 2 test files")
      end
    end

    context "with a fallback under --run" do
      let(:script) { "File.write(#{out_path.inspect}, ARGV.join(' ').inspect)" }

      before do
        file!("Gemfile.lock", "# changed\n")
        run_in_repo("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", script)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", script)).to eq(0)
      end

      it "runs the command bare" do
        expect(File.read(out_path)).to eq('""')
      end

      it "says it fell back" do
        expect(stderr.string).to include("falling back to the full suite")
      end
    end

    context "with a trigger firing alongside a selection under --run" do
      let(:script) { "File.write(#{out_path.inspect}, ARGV.join(' ').inspect)" }

      before do
        file!("lib/result.rb", "# changed\n")
        file!("lib/stale.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", script)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", script)).to eq(0)
      end

      it "runs the command bare, and only bare" do
        expect(File.read(out_path)).to eq('""')
      end

      it "names the trigger" do
        expect(stderr.string).to include("no longer exists")
      end

      it "says it fell back" do
        expect(stderr.string).to include("falling back to the full suite")
      end
    end

    context "with a runner it cannot run" do
      let(:missing) { File.join(tmp, "nope-does-not-exist") }

      before { file!("lib/result.rb", "# changed\n") }

      it "answers the shell's own code" do
        expect(run_in_repo("affected", "--input", json_path, "--run", missing)).to missing_command_status
      end

      it "names the command", if: RUBY_ENGINE == "ruby" do
        run_in_repo("affected", "--input", json_path, "--run", missing)

        expect(stderr.string).to include("cannot run #{missing.inspect}")
      end
    end

    it "propagates the runner's exit status" do
      file!("lib/result.rb", "# changed\n")
      expect(run_in_repo("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", "exit 3")).to eq(3)
    end

    it "speaks of one selected file in the singular" do
      file!("spec/result_spec.rb", "# changed\n")
      run_in_repo("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", "exit 0")

      expect(stderr.string).to include("running 1 test file\n")
    end

    it "exits non-zero for a runner killed by a signal" do
      skip "SIGKILL semantics are POSIX; Windows reports an exit status instead" if Gem.win_platform?

      file!("lib/result.rb", "# changed\n")
      script = "Process.kill(:KILL, Process.pid)"
      expect(run_in_repo("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", script)).to eq(1)
    end

    context "when nothing is selected under --run" do
      let(:script) { "File.write(#{out_path.inspect}, 'ran')" }

      before do
        file!("lib/quiet.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", script)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path, "--run", RbConfig.ruby, "-e", script)).to eq(0)
      end

      it "skips the runner" do
        expect(File.exist?(out_path)).to be(false)
      end

      it "says why" do
        expect(stderr.string).to include("no recorded test touches the changed code")
      end
    end

    context "with a command that is not on PATH" do
      before { file!("lib/result.rb", "# changed\n") }

      it "answers the shell's own code, like the run subcommand does" do
        expect(run_in_repo("affected", "--input", json_path, "--run", "definitely-not-a-command-xyz")).to eq(127)
      end

      it "names it", if: RUBY_ENGINE == "ruby" do
        run_in_repo("affected", "--input", json_path, "--run", "definitely-not-a-command-xyz")

        expect(stderr.string).to include("definitely-not-a-command-xyz")
      end
    end

    context "with no command after --run" do
      it "errors" do
        expect(run_in_repo("affected", "--input", json_path, "--run")).to eq(1)
      end

      it "says what was missing" do
        run_in_repo("affected", "--input", json_path, "--run")

        expect(stderr.string).to include("missing command after --run")
      end
    end

    context "with --run and --json together" do
      it "refuses to combine them" do
        expect(run_in_repo("affected", "--input", json_path, "--json", "--run", "true")).to eq(1)
      end

      it "names the flag it cannot honor" do
        run_in_repo("affected", "--input", json_path, "--json", "--run", "true")

        expect(stderr.string).to include("--json")
      end
    end

    context "with a bad base ref" do
      before { run_in_repo("affected", "--input", json_path, "--base", "no-such-ref") }

      it "errors" do
        expect(run_in_repo("affected", "--input", json_path, "--base", "no-such-ref")).to eq(1)
      end

      it "selects nothing" do
        expect(stdout.string).to be_empty
      end

      it "reports it as a git error" do
        expect(stderr.string).to include("git diff")
      end
    end

    context "when the document carries no contexts" do
      before do
        File.write(json_path, JSON.dump({"coverage" => {}}))
        file!("lib/result.rb", "# changed\n")
      end

      it "errors" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      end

      it "explains what to enable" do
        run_in_repo("affected", "--input", json_path)

        expect(stderr.string).to include("track_tests")
      end
    end

    [{"9" => "6"}, "junk"].each do |malformed|
      context "with #{malformed.inspect} for a per-file contexts table" do
        before do
          payload["coverage"][File.join(tmp, "lib/result.rb")]["contexts"] = malformed
          File.write(json_path, JSON.dump(payload))
          file!("lib/result.rb", "# changed\n")
        end

        it "errors" do
          expect(run_in_repo("affected", "--input", json_path)).to eq(1)
        end

        it "treats it as invalid input" do
          run_in_repo("affected", "--input", json_path)

          expect(stderr.string).to include("isn't valid")
        end
      end
    end

    context "with a wrong-typed entry" do
      before do
        payload["coverage"][File.join(tmp, "lib/result.rb")] = "junk"
        File.write(json_path, JSON.dump(payload))
        file!("lib/result.rb", "# changed\n")
      end

      it "errors" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      end

      it "treats it as invalid input" do
        run_in_repo("affected", "--input", json_path)

        expect(stderr.string).to eq(
          "simplecov affected: input file #{json_path.inspect} isn't valid JSON " \
          "(entry for lib/result.rb must be an object)\n"
        )
      end
    end

    context "with a non-object coverage section" do
      before do
        File.write(json_path, JSON.dump(payload.merge("coverage" => "junk")))
        file!("lib/result.rb", "# changed\n")
      end

      it "errors" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      end

      it "treats it as invalid input" do
        run_in_repo("affected", "--input", json_path)

        expect(stderr.string).to include('"coverage" must be an object')
      end
    end

    context "when git fails while listing untracked files" do
      before do
        failed = instance_double(Process::Status, success?: false)
        allow(Open3).to receive(:capture3).and_call_original
        allow(Open3).to receive(:capture3)
          .with("git", "-C", anything, "ls-files", any_args).and_return(["", "boom\n", failed])
        file!("lib/result.rb", "# changed\n")
      end

      it "errors" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      end

      it "relays what git said" do
        run_in_repo("affected", "--input", json_path)

        expect(stderr.string).to include("`git ls-files` failed: boom")
      end
    end

    context "when git cannot be run at all" do
      before { allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, "git") }

      it "errors" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      end

      it "says so" do
        run_in_repo("affected", "--input", json_path)

        expect(stderr.string).to include("cannot run git")
      end
    end

    context "when git vanishes between the root lookup and the diff" do
      before do
        allow(Open3).to receive(:capture3).and_call_original
        allow(Open3).to receive(:capture3)
          .with("git", "-C", anything, "diff", any_args).and_raise(Errno::ENOENT, "git")
      end

      it "errors" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(1)
      end

      it "says so" do
        run_in_repo("affected", "--input", json_path)

        expect(stderr.string).to include("cannot run git")
      end
    end

    it "documents itself in the usage text" do
      run("help")

      expect(stdout.string).to include("affected options:")
    end
  end
end

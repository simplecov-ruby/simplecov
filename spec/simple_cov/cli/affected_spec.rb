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
        "lib/boot.rb" => "# original\n", "lib/lineless.rb" => "# original\n",
        "lib/garbled.rb" => "# original\n",
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
          File.join(tmp, "lib/quiet.rb") => {"lines" => [0, "ignored"]},
          File.join(tmp, "lib/lineless.rb") => {"contexts" => {}},
          File.join(tmp, "lib/garbled.rb") => {"lines" => "1"},
          File.join(tmp, "lib/boot.rb") => {"lines" => [nil, 1, 0]},
          File.join(tmp, "lib/odd.rb") => {"lines" => [1], "contexts" => {"2" => "1"}},
          File.join(tmp, "lib/stale.rb") => {"lines" => [1], "contexts" => {"3" => "1"}},
          File.join(tmp, "lib/plain.rb") => {"lines" => [1], "contexts" => {"4" => "1"}},
          File.join(tmp, "lib/suffixless.rb") => {"lines" => [1], "contexts" => {"5" => "1"}},
          File.join(tmp, "lib/plain2.rb") => {"lines" => [1], "contexts" => {"4" => "1"}},
          File.join(tmp, "lib/aaa.rb") => {"lines" => [1], "contexts" => {"4" => "1"}}
        }
      }
    end

    def json_path = File.join(tmp, "coverage.json")

    def out_path = File.join(tmp, "out.txt")

    # A single-quoted path: JRuby on Windows hands a double quote inside an
    # argument to the child unescaped, which breaks the script it is part of.
    def write_out(expression) = "File.write('#{out_path}', #{expression})"

    def file!(path, content = "# original\n")
      full = File.join(tmp, path)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
    end

    def commit!(message)
      GitFixture.commit!(tmp, message)
    end

    def git_in_repo(*argv)
      GitFixture.git!("-C", tmp, *argv)
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
        GitFixture.git!("-C", tmp, "branch", "-m", "main", "trunk")
        GitFixture.git!("-C", tmp, "update-ref", "refs/remotes/origin/trunk", "HEAD")
        GitFixture.git!("-C", tmp, "symbolic-ref", "refs/remotes/origin/HEAD",
          "refs/remotes/origin/trunk")
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

      expect(JSON.parse(stdout.string)).to eq("full_suite" => false, "triggers" => [], "tests" => [], "reasons" => {})
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
        GitFixture.git!("-C", tmp, "switch", "-qc", "feature")
        GitFixture.git!("-C", tmp, "switch", "-q", "main")
        file!("lib/quiet.rb", "# changed on main\n")
        commit!("change quiet on main")
        GitFixture.git!("-C", tmp, "switch", "-q", "feature")
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
      let(:script) { write_out("Dir.pwd") }

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
            base: nil, run: nil, explain: false, global: [], by_file: false, rest: [])
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
        file!("spec/test_widget.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "recognises it by its own name, not by its path" do
        expect(stdout.string).to eq("spec/test_widget.rb\n")
      end

      it "says nothing on stderr" do
        expect(stderr.string).to be_empty
      end
    end

    context "with a changed test_helper.rb" do
      before do
        file!("spec/test_helper.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path)
      end

      it "selects nothing, since it defines no tests" do
        expect(stdout.string).to be_empty
      end

      it "falls back to the full suite" do
        expect(stderr.string).to include("spec/test_helper.rb changed but").and include("falling back to the full suite")
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

    context "with a changed file that ran only outside recorded tests" do
      before do
        file!("lib/boot.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "selects nothing" do
        expect(stdout.string).to be_empty
      end

      it "names the file" do
        expect(stderr.string).to include(
          "simplecov affected: lib/boot.rb changed but ran only outside recorded tests"
        )
      end

      it "falls back to the full suite" do
        expect(stderr.string).to include("falling back to the full suite")
      end
    end

    context "with a changed file the report carries no line counts for" do
      before do
        file!("lib/lineless.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path)
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path)).to eq(0)
      end

      it "names the file" do
        expect(stderr.string).to include("lib/lineless.rb changed but #{json_path} has no data for it")
      end

      it "falls back to the full suite" do
        expect(stderr.string).to include("falling back to the full suite")
      end
    end

    it "treats line counts that are not a list as no data" do
      file!("lib/garbled.rb", "# changed\n")
      run_in_repo("affected", "--input", json_path)

      expect(stderr.string).to include("lib/garbled.rb changed but #{json_path} has no data for it")
    end

    describe "narrowing a change to the methods it touched", :prism do
      let(:fixture_files) do
        super().merge("lib/widget.rb" => widget, "spec/small_spec.rb" => "# small\n", "spec/large_spec.rb" => "# large\n")
      end

      def widget
        <<~RUBY
          class Widget
            LIMIT = 3

            def small
              :small
            end

            def large
              :large
            end
          end
        RUBY
      end

      def record_widget(source: widget, lines: [1, 1, nil, 1, 1, nil, nil, 1, 1, nil, nil], tables: {"6" => "10", "7" => "100"})
        payload["contexts"] += ["spec/small_spec.rb:1", "spec/large_spec.rb:1"]
        entry = {"source" => source&.lines&.map(&:chomp), "lines" => lines, "contexts" => tables}.compact
        payload["coverage"][File.join(tmp, "lib/widget.rb")] = entry
        File.write(json_path, JSON.dump(payload))
      end

      def change_widget(from, to, *flags, **recorded)
        rewrite_widget(widget.sub(from, to), *flags, **recorded)
      end

      def rewrite_widget(content, *flags, **recorded)
        record_widget(**recorded)
        file!("lib/widget.rb", content)
        run_in_repo("affected", "--input", json_path, *flags)
      end

      it "selects only the tests that ran a changed method" do
        change_widget(":large\n", ":larger\n")

        expect(stdout.string).to eq("spec/large_spec.rb\n")
      end

      it "selects every test touching the file under --by-file" do
        change_widget(":large\n", ":larger\n", "--by-file")

        expect(stdout.string).to eq("spec/large_spec.rb\nspec/small_spec.rb\n")
      end

      it "selects for a change to a method's signature" do
        change_widget("def small", "def small(size = 1)")

        expect(stdout.string).to eq("spec/small_spec.rb\n")
      end

      it "falls back to the full suite for a changed line no recorded test ran" do
        change_widget("LIMIT = 3", "LIMIT = 4")

        expect(stderr.string).to include("lib/widget.rb changed in the statement at line 2, which ran only outside recorded tests")
      end

      it "falls back to the full suite for a changed line no recorded test ran under --by-file" do
        change_widget("LIMIT = 3", "LIMIT = 4", "--by-file")

        expect(stderr.string).to include("lib/widget.rb changed in the statement at line 2, which ran only outside recorded tests")
      end

      it "selects every test touching the file for a changed line a recorded test ran" do
        change_widget("LIMIT = 3", "LIMIT = 4", tables: {"6" => "12", "7" => "100"})

        expect([stdout.string, stderr.string]).to eq(["spec/large_spec.rb\nspec/small_spec.rb\n", ""])
      end

      it "falls back to the full suite for a constant added between two methods" do
        change_widget("  def large", "  OTHER = 5\n\n  def large")

        expect(stderr.string).to include("lib/widget.rb changed in the statement at line 1, which ran only outside recorded tests")
      end

      it "selects every test touching the file for a method added between two" do
        change_widget("  def large", "  def medium\n    :medium\n  end\n\n  def large")

        expect(stdout.string).to eq("spec/large_spec.rb\nspec/small_spec.rb\n")
      end

      it "narrows each of two changed methods" do
        rewrite_widget(widget.sub(":small\n", ":smaller\n").sub(":large\n", ":larger\n"), tables: {"6" => "10", "7" => "100", "4" => "2"})

        expect(stdout.string).to eq("spec/large_spec.rb\nspec/small_spec.rb\n")
      end

      it "narrows a change the recording already carries" do
        change_widget(":large\n", ":larger\n", source: widget.sub(":large\n", ":larger\n"))

        expect(stdout.string).to eq("spec/large_spec.rb\n")
      end

      it "falls back to the full suite for a changed method that ran only outside recorded tests" do
        change_widget(":small\n", ":smaller\n", tables: {"7" => "100"})

        expect(stderr.string).to include("lib/widget.rb changed but ran only outside recorded tests")
      end

      it "selects nothing for a changed method that never ran" do
        change_widget(":small\n", ":smaller\n", lines: [1, 1, nil, 1, 0, nil, nil, 1, 1, nil, nil], tables: {"7" => "100"})

        expect([stdout.string, stderr.string]).to eq(["", "simplecov affected: no recorded test touches the changed code\n"])
      end

      it "selects every test touching the file without the recorded source" do
        change_widget(":large\n", ":larger\n", source: nil)

        expect(stdout.string).to eq("spec/large_spec.rb\nspec/small_spec.rb\n")
      end

      it "falls back to the full suite for a changed line the recording already carries" do
        change_widget("LIMIT = 3", "LIMIT = 4", source: widget.sub("LIMIT = 3", "LIMIT = 4"))

        expect(stderr.string).to include("lib/widget.rb changed in the statement at line 2, which ran only outside recorded tests")
      end

      def change_comment(from, to)
        commented = widget.sub("  LIMIT", "  # The most widgets.\n  LIMIT").sub("    :large", "    # The large one.\n    :large")
        file!("lib/widget.rb", commented)
        git_in_repo("-c", "user.email=spec@example.com", "-c", "user.name=spec", "commit", "-qam", "comment widget")
        rewrite_widget(commented.sub(from, to), source: commented,
          lines: [1, nil, 1, nil, 1, 1, nil, nil, 1, nil, 1, nil, nil], tables: {"6" => "20", "7" => "400"})
        [stdout.string, stderr.string]
      end

      it "selects every test touching the file for an edited comment in the class body" do
        expect(change_comment("most", "fewest")).to eq(["spec/large_spec.rb\nspec/small_spec.rb\n", ""])
      end

      it "selects only the tests that ran a method for an edited comment at its top" do
        expect(change_comment("large one", "big one")).to eq(["spec/large_spec.rb\n", ""])
      end

      it "selects every test touching a deleted file" do
        record_widget
        FileUtils.rm(File.join(tmp, "lib/widget.rb"))
        run_in_repo("affected", "--input", json_path)

        expect(stdout.string).to eq("spec/large_spec.rb\nspec/small_spec.rb\n")
      end

      it "selects every test touching a file added since the base" do
        git_in_repo("rm", "--cached", "-q", "lib/widget.rb")
        git_in_repo("-c", "user.email=spec@example.com", "-c", "user.name=spec", "commit", "-qm", "drop widget")
        change_widget(":large\n", ":larger\n")

        expect(stdout.string).to eq("spec/large_spec.rb\nspec/small_spec.rb\n")
      end

      it "narrows from a subdirectory" do
        record_widget
        file!("lib/widget.rb", widget.sub(":large\n", ":larger\n"))
        run_in_spec_dir("affected", "--input", json_path)

        expect(stdout.string).to eq("spec/large_spec.rb\n")
      end

      def narrowed(path, recorded, opts = {})
        described_class::Affected::Selection.narrowed(path, {"source" => recorded}, {root: tmp, opts: {by_file: false, **opts}})&.first
      end

      it "masks the first counted line of each rewritten statement" do
        mask = described_class::Affected::Selection.load_time_mask({"lines" => [nil, 1, nil, 1]}, [1, 2, 3, 4])

        expect(mask).to eq(0b1010)
      end

      it "masks nothing without line counts" do
        masks = [{}, {"lines" => "1"}].map { |entry| described_class::Affected::Selection.load_time_mask(entry, [1]) }

        expect(masks).to eq([nil, nil])
      end

      it "narrows against the recording alone when there is no base to compare" do
        file!("lib/widget.rb", widget.sub(":large\n", ":larger\n"))

        expect(narrowed("lib/widget.rb", widget.lines.map(&:chomp))).to eq(0b11 << 8)
      end

      it "narrows nothing against a base it cannot name" do
        file!("lib/widget.rb", widget.sub(":large\n", ":larger\n"))

        expect(narrowed("lib/widget.rb", widget.lines.map(&:chomp), {merge_base: nil})).to be_nil
      end

      it "narrows no file that is not Ruby" do
        file!("lib/widget.erb", widget.sub(":large\n", ":larger\n"))

        expect(narrowed("lib/widget.erb", widget.lines.map(&:chomp))).to be_nil
      end

      it "narrows nothing from recorded source that is not a list" do
        expect(narrowed("lib/widget.rb", "class Widget")).to be_nil
      end

      it "narrows nothing from recorded source with a line that is not a string" do
        file!("lib/solo.rb", "def solo\n  :solo\nend\n")

        expect(narrowed("lib/solo.rb", ["def solo", 7, "end"])).to be_nil
      end

      it "narrows nothing for a deleted file" do
        FileUtils.rm(File.join(tmp, "lib/widget.rb"))

        expect(narrowed("lib/widget.rb", ["def solo", "  :solo", "end"])).to be_nil
      end

      it "reads the base source from the merge base, not the index" do
        file!("lib/widget.rb", widget.sub(":large\n", ":larger\n"))
        git_in_repo("add", "lib/widget.rb")
        head = Open3.capture2("git", "-C", tmp, "rev-parse", "HEAD").first.strip

        expect(described_class::Affected::Selection.base_source("lib/widget.rb", head, tmp)).to eq(widget)
      end

      it "finds no base source for a file the base lacks" do
        head = Open3.capture2("git", "-C", tmp, "rev-parse", "HEAD").first.strip

        expect(described_class::Affected::Selection.base_source("lib/missing.rb", head, tmp)).to be_nil
      end

      it "names no merge base for a ref git cannot resolve" do
        expect(described_class::Affected::ChangedFiles.merge_base(tmp, "no-such-ref")).to be_nil
      end

      it "compares against no base it cannot name" do
        expect(described_class::Affected::Selection.base_source("lib/widget.rb", nil, tmp)).to be_nil
      end
    end

    context "with a changed file declared global" do
      before do
        file!("lib/result.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path, "--global", "config/**", "--global", "lib/{result,odd}.rb")
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path, "--global", "lib/{result,odd}.rb")).to eq(0)
      end

      it "selects nothing" do
        expect(stdout.string).to be_empty
      end

      it "names the file and the pattern it matched" do
        expect(stderr.string).to include("simplecov affected: lib/result.rb changed and matches --global lib/{result,odd}.rb\n")
      end

      it "falls back to the full suite" do
        expect(stderr.string).to include("falling back to the full suite")
      end
    end

    it "needs no well-formed data for a file declared global" do
      payload["coverage"][File.join(tmp, "lib/result.rb")]["contexts"] = {"99" => "1"}
      File.write(json_path, JSON.dump(payload))
      file!("lib/result.rb", "# changed\n")

      expect(run_in_repo("affected", "--input", json_path, "--global", "lib/result.rb")).to eq(0)
    end

    it "matches a global pattern across directories" do
      file!("config/initializers/deep/setup.rb", "# new\n")
      run_in_repo("affected", "--input", json_path, "--global", "config/**/*.rb")

      expect(stderr.string).to include("config/initializers/deep/setup.rb changed and matches --global config/**/*.rb")
    end

    it "holds a test file to a global pattern too" do
      file!("spec/result_spec.rb", "# changed\n")
      run_in_repo("affected", "--input", json_path, "--global", "spec/*_spec.rb")

      expect(stdout.string).to be_empty
    end

    it "leaves a file no global pattern matches to the selection" do
      file!("lib/result.rb", "# changed\n")
      run_in_repo("affected", "--input", json_path, "--global", "lib/*.yml")

      expect(stdout.string).to eq("spec/result_spec.rb\nspec/source_file_spec.rb\n")
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

      let(:reasons) do
        {"spec/result_spec.rb" => {"lib/result.rb" => ["spec/result_spec.rb:42"]},
         "spec/source_file_spec.rb" => {"lib/result.rb" => ["spec/source_file_spec.rb:12"]}}
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path, "--json")).to eq(0)
      end

      it "emits it as a JSON object" do
        run_in_repo("affected", "--input", json_path, "--json")

        expect(JSON.parse(stdout.string)).to eq("full_suite" => false, "triggers" => [],
          "tests" => ["spec/result_spec.rb", "spec/source_file_spec.rb"], "reasons" => reasons)
      end
    end

    context "with --explain" do
      before do
        file!("lib/result.rb", "# changed\n")
        file!("lib/plain2.rb", "# changed\n")
        file!("lib/aaa.rb", "# new\n")
        file!("spec/brand_new_spec.rb")
        run_in_repo("affected", "--input", json_path, "--explain")
      end

      it "succeeds" do
        expect(run_in_repo("affected", "--input", json_path, "--explain")).to eq(0)
      end

      it "still lists only the selection on stdout" do
        expect(stdout.string).to eq("spec/brand_new_spec.rb\nspec/result_spec.rb\nspec/source_file_spec.rb\ntoplevel_test.rb\n")
      end

      it "names the changed file and the recorded tests behind each selected file" do
        expect(stderr.string).to include(
          "simplecov affected: spec/result_spec.rb runs for lib/result.rb (spec/result_spec.rb:42)\n"
        )
      end

      it "names a changed test file as its own reason" do
        expect(stderr.string).to include("simplecov affected: spec/brand_new_spec.rb runs because it changed\n")
      end

      it "explains each selected file once per changed file, in order" do
        expect(stderr.string.lines.map { |line| line[/runs.*/] }).to eq([
          "runs because it changed", "runs for lib/result.rb (spec/result_spec.rb:42)",
          "runs for lib/result.rb (spec/source_file_spec.rb:12)", "runs for lib/aaa.rb (toplevel_test.rb:99)",
          "runs for lib/plain2.rb (toplevel_test.rb:99)"
        ])
      end
    end

    it "explains nothing on a fallback, even with files it would have selected" do
      file!("Gemfile.lock", "# changed\n")
      file!("lib/result.rb", "# changed\n")
      run_in_repo("affected", "--input", json_path, "--explain")

      expect(stderr.string).not_to include(" runs ")
    end

    it "carries no reasons on a fallback under --json" do
      file!("Gemfile.lock", "# changed\n")
      file!("lib/result.rb", "# changed\n")
      run_in_repo("affected", "--input", json_path, "--json")

      expect(JSON.parse(stdout.string).fetch("reasons")).to eq({})
    end

    it "gives a changed test file itself as its reason under --json" do
      file!("spec/result_spec.rb", "# changed\n")
      run_in_repo("affected", "--input", json_path, "--json")

      expect(JSON.parse(stdout.string).fetch("reasons")).to eq("spec/result_spec.rb" => {"spec/result_spec.rb" => []})
    end

    it "resolves a report key spelled with a parent step" do
      payload["coverage"][File.join(tmp, "lib", "..", "lib", "result.rb")] = payload["coverage"].delete(File.join(tmp, "lib/result.rb"))
      File.write(json_path, JSON.dump(payload))
      file!("lib/result.rb", "# changed\n")
      run_in_repo("affected", "--input", json_path)

      expect(stdout.string).to eq("spec/result_spec.rb\nspec/source_file_spec.rb\n")
    end

    context "with several recorded tests in one selected file" do
      before do
        payload["coverage"][File.join(tmp, "lib/result.rb")]["contexts"] = {"4" => "2", "0" => "6", "5" => "2", "1" => "4"}
        payload["contexts"][4] = "spec/result_spec.rb:7"
        payload["contexts"][5] = "spec/result_spec.rb"
        File.write(json_path, JSON.dump(payload))
        file!("lib/result.rb", "# changed\n")
        run_in_repo("affected", "--input", json_path, "--explain")
      end

      it "lists each in line order, the file's own loading first" do
        expect(stderr.string).to include("spec/result_spec.rb runs for lib/result.rb " \
                                         "(spec/result_spec.rb, spec/result_spec.rb:7, spec/result_spec.rb:42)\n")
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
      let(:script) { write_out("ARGV.join(' ')") }

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
      let(:script) { write_out("ARGV.join(' ').inspect") }

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
      let(:script) { write_out("ARGV.join(' ').inspect") }

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
      let(:script) { write_out("'ran'") }

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

# frozen_string_literal: true

require "coverage"
require "helper"
require "simplecov/cli"
require "tmpdir"

RSpec.describe SimpleCov::CLI::Dotfile, mutant_expression: "SimpleCov::CLI::Dotfile*" do
  def in_project(dotfile_body = nil)
    Dir.mktmpdir("simplecov-dotfile-spec-") do |tmp|
      File.write(File.join(tmp, ".simplecov"), dotfile_body) if dotfile_body
      Dir.chdir(tmp) { yield tmp }
    end
  end

  def configured(name)
    SimpleCov.instance_variable_get(:"@#{name}")
  end

  def with_configured(name, value)
    ivar = :"@#{name}"
    previous = SimpleCov.instance_variable_get(ivar)
    SimpleCov.instance_variable_set(ivar, value)
    yield
  ensure
    SimpleCov.instance_variable_set(ivar, previous)
  end

  describe ".coverage_dir" do
    it "reads the dotfile's configured directory" do
      in_project(%(SimpleCov.coverage_dir "my/reports"\n)) do
        expect(described_class.coverage_dir).to eq("my/reports")
      end
    end

    it "falls back to the default directory with no dotfile at all" do
      in_project { expect(described_class.coverage_dir).to eq("coverage") }
    end

    it "stays quiet with no dotfile at all" do
      in_project { expect { described_class.coverage_dir }.not_to output.to_stderr }
    end

    it "reads a directory configured inside a start block" do
      in_project("SimpleCov.start { coverage_dir 'from/start' }\n") do
        expect(described_class.coverage_dir).to eq("from/start")
      end
    end

    it "falls back to the default directory when the dotfile raises" do
      in_project(%(raise "boom"\n)) do
        expect(without_stderr { described_class.coverage_dir }).to eq("coverage")
      end
    end

    it "warns when the dotfile raises" do
      in_project(%(raise "boom"\n)) do
        expect { described_class.coverage_dir }
          .to output(/simplecov: failed to read coverage_dir from .*\.simplecov: RuntimeError: boom/).to_stderr
      end
    end

    it "lets the dotfile's directory win over the host process's own setting" do
      with_configured(:coverage_dir, "host/reports") do
        in_project(%(SimpleCov.coverage_dir "clobbered"\n)) { expect(described_class.coverage_dir).to eq("clobbered") }
      end
    end

    it "restores the host process's own setting, whatever the dotfile did to it" do
      with_configured(:coverage_dir, "host/reports") do
        in_project(%(SimpleCov.coverage_dir "clobbered"\n)) { described_class.coverage_dir }
        expect(configured(:coverage_dir)).to eq("host/reports")
      end
    end
  end

  describe ".baseline_file" do
    it "reads the dotfile's configured baseline path" do
      in_project(%(SimpleCov.baseline_file "config/floors.yml"\n)) do
        expect(described_class.baseline_file).to eq("config/floors.yml")
      end
    end

    it "falls back to the default filename with no dotfile at all" do
      in_project { expect(described_class.baseline_file).to eq(SimpleCov::Baseline::DEFAULT_FILENAME) }
    end

    it "stays quiet with no dotfile at all" do
      in_project { expect { described_class.baseline_file }.not_to output.to_stderr }
    end

    it "falls back to the default filename when the dotfile raises" do
      in_project(%(raise "boom"\n)) do
        expect(without_stderr { described_class.baseline_file }).to eq(SimpleCov::Baseline::DEFAULT_FILENAME)
      end
    end

    it "warns when the dotfile raises" do
      in_project(%(raise "boom"\n)) do
        expect { described_class.baseline_file }
          .to output(%r{simplecov: failed to read baseline_file from .*/\.simplecov: RuntimeError: boom}).to_stderr
      end
    end

    it "lets the dotfile's baseline path win over the host process's own setting" do
      with_configured(:baseline_file, "host.yml") do
        in_project(%(SimpleCov.baseline_file "clobbered.yml"\n)) { expect(described_class.baseline_file).to eq("clobbered.yml") }
      end
    end

    it "restores the host process's own setting, whatever the dotfile did to it" do
      with_configured(:baseline_file, "host.yml") do
        in_project(%(SimpleCov.baseline_file "clobbered.yml"\n)) { described_class.baseline_file }
        expect(configured(:baseline_file)).to eq("host.yml")
      end
    end
  end

  describe ".production_coverage" do
    it "reads the dotfile's configured store" do
      in_project(%(SimpleCov.production_coverage "/var/data/prod.json"\n)) do
        expect(described_class.production_coverage).to eq(File.expand_path("/var/data/prod.json"))
      end
    end

    it "answers nil with no dotfile at all" do
      in_project { expect(described_class.production_coverage).to be_nil }
    end

    it "stays quiet with no dotfile at all" do
      in_project { expect { described_class.production_coverage }.not_to output.to_stderr }
    end

    it "answers nil when the dotfile names no store" do
      in_project("# configuration that names no production store\n") do
        expect(described_class.production_coverage).to be_nil
      end
    end

    it "answers nil when the dotfile raises" do
      in_project(%(raise "boom"\n)) do
        expect(without_stderr { described_class.production_coverage }).to be_nil
      end
    end

    it "warns when the dotfile raises" do
      in_project(%(raise "boom"\n)) do
        expect { described_class.production_coverage }
          .to output(%r{failed to read production_coverage from .*/\.simplecov: RuntimeError: boom}).to_stderr
      end
    end

    it "lets the dotfile's store win over the host process's own setting" do
      with_configured(:production_coverage, "/host.json") do
        in_project(%(SimpleCov.production_coverage "/clobbered.json"\n)) do
          expect(described_class.production_coverage).to eq(File.expand_path("/clobbered.json"))
        end
      end
    end

    it "restores the host process's own setting, whatever the dotfile did to it" do
      with_configured(:production_coverage, "/host.json") do
        in_project(%(SimpleCov.production_coverage "/clobbered.json"\n)) { described_class.production_coverage }
        expect(configured(:production_coverage)).to eq("/host.json")
      end
    end
  end

  describe "a dotfile that will not parse" do
    let(:unparsable) { "SimpleCov.start do\n" }

    it "falls back to the default directory" do
      in_project(unparsable) { expect(without_stderr { described_class.coverage_dir }).to eq("coverage") }
    end

    it "warns about the directory read" do
      in_project(unparsable) do
        expect { described_class.coverage_dir }.to output(/failed to read coverage_dir.*SyntaxError/m).to_stderr
      end
    end

    it "falls back to the default baseline filename" do
      in_project(unparsable) do
        expect(without_stderr { described_class.baseline_file }).to eq(SimpleCov::Baseline::DEFAULT_FILENAME)
      end
    end

    it "warns about the baseline read" do
      in_project(unparsable) do
        expect { described_class.baseline_file }.to output(/failed to read baseline_file.*SyntaxError/m).to_stderr
      end
    end

    it "answers no production store" do
      in_project(unparsable) { expect(without_stderr { described_class.production_coverage }).to be_nil }
    end

    it "warns about the production store read" do
      in_project(unparsable) do
        expect { described_class.production_coverage }.to output(/failed to read production_coverage.*SyntaxError/m).to_stderr
      end
    end
  end

  describe ".find" do
    def in_nested_dir(tmp)
      nested = File.join(tmp, "a", "b")
      FileUtils.mkdir_p(nested)
      Dir.chdir(nested) { yield }
    end

    it "finds the dotfile in the working directory" do
      in_project("# empty\n") do |tmp|
        expect(File.realpath(described_class.find)).to eq(File.realpath(File.join(tmp, ".simplecov")))
      end
    end

    it "walks up to an ancestor's dotfile" do
      in_project("# empty\n") do |tmp|
        in_nested_dir(tmp) { expect(File.realpath(described_class.find)).to eq(File.realpath(File.join(tmp, ".simplecov"))) }
      end
    end

    it "answers nil after walking all the way to the filesystem root" do
      in_project { expect(described_class.find).to be_nil }
    end

    it "answers a plain path string" do
      in_project("# empty\n") { expect(described_class.find).to be_a(String) }
    end
  end

  describe "the neutered load" do
    it "neuters the tracking half, so reading cannot begin measuring" do
      before = SimpleCov.process_start_time
      in_project("SimpleCov.start\n") { described_class.coverage_dir }
      expect(SimpleCov.process_start_time).to eq(before)
    end

    it "neuters both halves for every reader, not just the first" do
      before = SimpleCov.process_start_time
      %i[baseline_file production_coverage].each do |reader|
        in_project("SimpleCov.start\n") { described_class.public_send(reader) }
        expect(SimpleCov.process_start_time).to(eq(before), "for #{reader}")
      end
    end

    it "neuters the at_exit half, so reading cannot arm the report" do
      with_configured(:at_exit_hook_installed, nil) do
        in_project("SimpleCov.start\n") { described_class.coverage_dir }
        expect(configured(:at_exit_hook_installed)).to be_nil
      end
    end

    it "gives SimpleCov its real start back afterwards" do
      original = SimpleCov.singleton_class.instance_method(:start_tracking)
      in_project("SimpleCov.start\n") { described_class.coverage_dir }
      expect(SimpleCov.singleton_class.instance_method(:start_tracking)).to eq(original)
    end

    it "gives SimpleCov its real at_exit installer back even when the dotfile raises" do
      original = SimpleCov.singleton_class.instance_method(:install_at_exit_hook)
      in_project(%(raise "boom"\n)) { without_stderr { described_class.coverage_dir } }
      expect(SimpleCov.singleton_class.instance_method(:install_at_exit_hook)).to eq(original)
    end

    context "when the host process has warnings turned on" do
      let(:levels) { [] }

      around do |example|
        previous = $VERBOSE
        $VERBOSE = true
        example.run
      ensure
        $VERBOSE = previous
      end

      before do
        allow(SimpleCov.singleton_class).to receive(:define_method).and_wrap_original do |original, *args, &block|
          levels << $VERBOSE
          original.call(*args, &block)
        end
      end

      it "silences every redefinition" do
        in_project("SimpleCov.start\n") { described_class.coverage_dir }
        expect(levels).to eq([nil, nil, nil, nil])
      end

      it "restores the warning level afterwards" do
        in_project("SimpleCov.start\n") { described_class.coverage_dir }
        expect($VERBOSE).to be(true)
      end
    end
  end

  describe "the environment the dotfile sees" do
    let(:reporting_dotfile) do
      <<~RUBY
        File.write("seen.txt", [ENV["SIMPLECOV_NO_DEFAULTS"], ENV["SIMPLECOV_CLI"]].inspect)
      RUBY
    end

    def env_seen_by(reader)
      in_project(reporting_dotfile) do |tmp|
        described_class.public_send(reader)
        File.read(File.join(tmp, "seen.txt"))
      end
    end

    it "loads it with defaults off and the CLI marker on, whichever setting is being read" do
      %i[coverage_dir baseline_file production_coverage].each do |reader|
        expect(env_seen_by(reader)).to(eq(%(["1", "1"])), "for #{reader}")
      end
    end

    it "restores SIMPLECOV_NO_DEFAULTS to what the host had set" do
      with_env("SIMPLECOV_NO_DEFAULTS" => "host", "SIMPLECOV_CLI" => "host-cli") do
        in_project("# empty\n") { described_class.coverage_dir }
        expect(ENV.fetch("SIMPLECOV_NO_DEFAULTS")).to eq("host")
      end
    end

    it "restores SIMPLECOV_CLI to what the host had set" do
      with_env("SIMPLECOV_NO_DEFAULTS" => "host", "SIMPLECOV_CLI" => "host-cli") do
        in_project("# empty\n") { described_class.coverage_dir }
        expect(ENV.fetch("SIMPLECOV_CLI")).to eq("host-cli")
      end
    end

    it "loads simplecov inside the guard, before the read runs" do
      allow(described_class).to receive(:load_simplecov).and_call_original
      in_project("# empty\n") { described_class.coverage_dir }
      expect(described_class).to have_received(:load_simplecov)
    end

    it "restores SIMPLECOV_NO_DEFAULTS to unset when the host had neither" do
      with_env("SIMPLECOV_NO_DEFAULTS" => nil, "SIMPLECOV_CLI" => nil) do
        in_project("# empty\n") { described_class.coverage_dir }
        expect(ENV.fetch("SIMPLECOV_NO_DEFAULTS", nil)).to be_nil
      end
    end

    it "restores SIMPLECOV_CLI to unset when the host had neither" do
      with_env("SIMPLECOV_NO_DEFAULTS" => nil, "SIMPLECOV_CLI" => nil) do
        in_project("# empty\n") { described_class.coverage_dir }
        expect(ENV.fetch("SIMPLECOV_CLI", nil)).to be_nil
      end
    end
  end
end

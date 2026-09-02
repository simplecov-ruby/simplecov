# frozen_string_literal: true

require "helper"
require "simplecov/cli"
require "stringio"

RSpec.describe SimpleCov::CLI::CommandHelpers, mutant_expression: "SimpleCov::CLI::CommandHelpers*" do
  let(:host) do
    Module.new do
      def self.name = "SimpleCov::CLI::Pretend"
      extend SimpleCov::CLI::CommandHelpers
    end
  end

  describe ".build_parser" do
    it "wires --help into every parser it builds" do
      expect { host.build_parser.parse(["--help"]) }
        .to raise_error(SimpleCov::CLI::CommandHelpers::HelpRequested)
    end

    it "answers -h the same way" do
      expect { host.build_parser.parse(["-h"]) }
        .to raise_error(SimpleCov::CLI::CommandHelpers::HelpRequested)
    end

    it "yields the parser it is building to the command's own options" do
      seen = nil

      parser = host.build_parser { |own| seen = own }

      expect(seen).to be(parser)
    end

    it "builds a parser for a command with no options of its own" do
      expect(host.build_parser).to be_a(OptionParser)
    end
  end

  describe ".quiet_option" do
    it "declares the long form and its short alias, both setting :quiet" do
      opts = {quiet: false}
      parser = host.build_parser { |own| host.quiet_option(own, opts) }

      parser.parse(["--quiet"])

      expect(opts).to eq(quiet: true)
    end
  end

  describe ".one?" do
    subject(:helpers) { Module.new { extend SimpleCov::CLI::CommandHelpers } }

    it "is true only for exactly one" do
      expect(helpers.one?(1)).to be(true)
    end

    it "is false for none" do
      expect(helpers.one?(0)).to be(false)
    end

    it "is false for several" do
      expect(helpers.one?(2)).to be(false)
    end
  end

  describe "#on_help" do
    ["--help", "-h"].each do |flag|
      it "raises HelpRequested for #{flag}" do
        parser = host.build_parser
        expect { parser.parse([flag]) }
          .to raise_error(SimpleCov::CLI::CommandHelpers::HelpRequested)
      end
    end
  end

  describe "#command_name" do
    it "names the command after the last segment of the module, downcased" do
      expect(host.command_name).to eq("pretend")
    end
  end

  describe "#parse_common" do
    it "seeds the shared defaults" do
      opts, = host.parse_common([])
      expect(opts).to eq(input: SimpleCov::CLI.default_input, json: false, no_color: false)
    end

    it "lets a command's own defaults join the shared ones" do
      opts, = host.parse_common([], threshold: 2.5)
      expect(opts).to include(threshold: 2.5, json: false)
    end

    it "returns the positional arguments after the flags, in order" do
      _opts, rest = host.parse_common(["--json", "first", "second"])
      expect(rest).to eq(%w[first second])
    end

    it "reads the shared trio" do
      opts, = host.parse_common(["--input", "cov.json", "--json", "--no-color"])
      expect(opts).to include(input: "cov.json", json: true, no_color: true)
    end

    it "yields the parser so a command can add its own options" do
      opts, = parse_only_mine

      expect(opts).to include(mine: true)
    end

    it "yields the very options hash it answers" do
      opts, = parse_only_mine

      expect(yielded_options.first).to be(opts)
    end

    def yielded_options
      @yielded_options ||= []
    end

    def parse_only_mine
      host.parse_common(["--only-mine"]) do |parser, options|
        yielded_options << options
        parser.on("--only-mine") { options[:mine] = true }
      end
    end
  end

  describe "#stats_row" do
    it "labels, aligns and counts the row" do
      expect(host.stats_row("lines", "80.00%", 8, 10)).to eq("  lines:  80.00% (8 / 10)")
    end

    it "reads a count that carries trailing text" do
      expect(host.stats_row("branches", "50.00%", "3 of them", "6 total")).to eq("  branches: 50.00% (3 / 6)")
    end
  end

  describe "#recorded_contexts" do
    let(:stderr) { StringIO.new }

    it "answers the recorded contexts" do
      contexts = %w[a_spec.rb:1 b_spec.rb:2]
      expect(host.recorded_contexts({"contexts" => contexts}, {input: "cov.json"}, stderr)).to eq(contexts)
    end

    context "when nothing was recorded" do
      it "answers nothing" do
        expect(host.recorded_contexts({}, {input: "cov.json"}, stderr)).to be_nil
      end

      it "names the report it looked in" do
        host.recorded_contexts({}, {input: "cov.json"}, stderr)

        expect(stderr.string).to include("no test contexts recorded in cov.json")
      end

      it "points at the switch that records them" do
        host.recorded_contexts({}, {input: "cov.json"}, stderr)

        expect(stderr.string).to include("track_tests")
      end
    end

    context "with a context list that is not strings" do
      it "answers nothing" do
        expect(host.recorded_contexts({"contexts" => [1, 2]}, {input: "cov.json"}, stderr)).to be_nil
      end

      it "says what the list should have held" do
        host.recorded_contexts({"contexts" => [1, 2]}, {input: "cov.json"}, stderr)

        expect(stderr.string).to include('"contexts" must be an array of strings')
      end
    end

    context "with contexts that are not a list at all" do
      it "answers nothing" do
        expect(host.recorded_contexts({"contexts" => "a_spec.rb"}, {input: "cov.json"}, stderr)).to be_nil
      end

      it "says what the list should have held" do
        host.recorded_contexts({"contexts" => "a_spec.rb"}, {input: "cov.json"}, stderr)

        expect(stderr.string).to include('"contexts" must be an array of strings')
      end
    end
  end
end

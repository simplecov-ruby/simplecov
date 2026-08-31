# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::UnloadedFileInjector do
  let(:fixture_root) { File.expand_path("fixtures", __dir__) }
  let(:sample) { File.join(fixture_root, "sample.rb") }

  describe ".discover" do
    context "with a directory of its own" do
      let(:root) { Dir.mktmpdir("injector-discover") }

      before do
        FileUtils.mkdir_p(File.join(root, "lib"))
        File.write(File.join(root, "lib/a.rb"), "a = 1\n")
        File.write(File.join(root, "lib/b.rb"), "b = 2\n")
      end

      after { FileUtils.remove_entry(root) }

      it "ignores a glob that was never given" do
        expect(described_class.discover(["lib/a.rb", nil], root: root))
          .to eq([File.join(root, "lib/a.rb")])
      end

      it "answers each path once, however many globs found it" do
        expect(described_class.discover(["lib/a.rb", "lib/*.rb"], root: root))
          .to contain_exactly(File.join(root, "lib/a.rb"), File.join(root, "lib/b.rb"))
      end

      it "drops the paths a path-only filter would exclude" do
        expect(described_class.discover(["lib/*.rb"], root: root, reject: [SimpleCov::StringFilter.new("a.rb")]))
          .to eq([File.join(root, "lib/b.rb")])
      end

      it "builds no source file when there is nothing to reject" do
        allow(SimpleCov::SourceFile).to receive(:new).and_call_original

        described_class.discover(["lib/*.rb"], root: root, reject: [])
        expect(SimpleCov::SourceFile).not_to have_received(:new)
      end
    end

    it "expands globs into absolute paths relative to the given root" do
      expect(described_class.discover(["sample.rb"], root: fixture_root)).to eq([sample])
    end

    it "resolves against that root regardless of the working directory" do
      Dir.chdir(Dir.tmpdir) do
        expect(described_class.discover(["sample.rb"], root: fixture_root)).to eq([sample])
      end
    end

    it "ignores nil globs and de-duplicates overlapping ones" do
      expect(described_class.discover([nil, "sample.rb", "sample.rb"], root: fixture_root)).to eq([sample])
    end
  end

  describe ".call" do
    it "passes the caller's choice of synthesis through" do
      allow(SimpleCov::SimulateCoverage).to receive(:call).and_return({"lines" => []})

      described_class.call({}, [sample], synthesize: true, lines: false)
      expect(SimpleCov::SimulateCoverage).to have_received(:call).with(sample, synthesize: true, lines: false)
    end

    it "simulates coverage for paths the result doesn't carry" do
      coverage, injected = described_class.call({}, [sample], synthesize: false, lines: true)

      expect(injected).to eq(Set[sample])
      expect(coverage[sample]["lines"]).to be_an(Array)
    end

    it "carries on past a path the result already carries" do
      Dir.mktmpdir("injector-call") do |dir|
        other = File.join(dir, "other.rb")
        File.write(other, "2\n")

        _coverage, injected = described_class.call({sample => {"lines" => [1]}}, [sample, other],
                                                   synthesize: false, lines: true)

        expect(injected).to eq(Set[other])
      end
    end

    it "leaves paths the result already carries alone" do
      existing = {sample => {"lines" => [1, 1]}}
      coverage, injected = described_class.call(existing, [sample], synthesize: false, lines: true)

      expect(injected).to be_empty
      expect(coverage[sample]).to eq("lines" => [1, 1])
    end

    it "does not mutate the coverage it was given" do
      original = {}
      described_class.call(original, [sample], synthesize: false, lines: true)

      expect(original).to be_empty
    end

    it "passes the criteria through to SimulateCoverage" do
      coverage, = described_class.call({}, [sample], synthesize: false, lines: false)

      expect(coverage[sample]).not_to have_key("lines")
      expect(coverage[sample]["branches"]).to be_empty
    end
  end

  describe ".rejected?" do
    it "is true when any filter matches the path" do
      filters = [SimpleCov::StringFilter.new("nothing"), SimpleCov::StringFilter.new("sample.rb")]
      expect(described_class.rejected?(sample, filters)).to be(true)
    end

    it "is false when none does" do
      expect(described_class.rejected?(sample, [SimpleCov::StringFilter.new("zzz")])).to be(false)
    end

    it "hands the filter a file marked as never loaded, with no coverage" do
      seen = nil
      described_class.rejected?(sample, [SimpleCov::BlockFilter.new(->(file) { seen = file and false })])

      expect(seen.project_filename).to end_with("sample.rb")
      expect(seen).to be_not_loaded
      expect(seen.coverage_data).to eq("lines" => [])
    end

    it "is false when there are no filters at all" do
      expect(described_class.rejected?(sample, [])).to be(false)
    end
  end
end

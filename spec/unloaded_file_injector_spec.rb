# frozen_string_literal: true

require "helper"

# The injector takes root, globs and criteria as arguments rather than reading
# them off the SimpleCov singleton, because the merge step runs it on behalf of
# processes whose configuration it may not share. See #1250.
RSpec.describe SimpleCov::UnloadedFileInjector do
  let(:fixture_root) { File.expand_path("fixtures", __dir__) }
  let(:sample) { File.join(fixture_root, "sample.rb") }

  describe ".discover" do
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
    it "simulates coverage for paths the result doesn't carry" do
      coverage, injected = described_class.call({}, [sample], synthesize: false, lines: true)

      expect(injected).to eq(Set[sample])
      expect(coverage[sample]["lines"]).to be_an(Array)
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
end

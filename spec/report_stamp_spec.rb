# frozen_string_literal: true

require "helper"
require "tmpdir"

RSpec.describe SimpleCov::ReportStamp do
  describe ".path" do
    it "lives inside the coverage path" do
      expect(described_class.path).to eq(File.join(SimpleCov.coverage_path, ".report_stamp"))
    end
  end

  describe ".touch" do
    it "creates the stamp file" do
      Dir.mktmpdir("report-stamp-spec-") do |dir|
        allow(SimpleCov).to receive(:coverage_path).and_return(dir)

        described_class.touch

        expect(File).to exist(File.join(dir, ".report_stamp"))
      end
    end

    # The stamp only powers the deferral heuristic, so a read-only or
    # vanished coverage dir must not crash the reporting that writes it.
    it "swallows filesystem errors" do
      allow(FileUtils).to receive(:touch).and_raise(Errno::EACCES)

      expect { described_class.touch }.not_to raise_error
    end
  end
end

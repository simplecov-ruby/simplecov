require "helper"

describe SimpleCov::Configuration do
  describe "#tracked_files" do
    context "when configured" do
      let(:glob) { "{app,lib}/**/*.rb" }

      before { SimpleCov.track_files(glob) }

      it "returns the configured glob" do
        expect(SimpleCov.tracked_files).to eq glob
      end

      context "and configured again with nil" do
        before { SimpleCov.track_files(nil) }

        it "returns nil" do
          expect(SimpleCov.tracked_files).to be_nil
        end
      end
    end

    context "when unconfigured" do
      it "returns nil" do
        expect(SimpleCov.tracked_files).to be_nil
      end
    end
  end
end

require "helper"

describe SimpleCov::LastRun do
  subject { SimpleCov::LastRun }

  it "defines a last_run_path" do
    expect(subject.last_run_path).to eq(File.join(SimpleCov.coverage_path, ".last_run.json"))
  end

  it "writes json to its last_run_path" do
    json = []
    subject.write(json)
    expect(File.read(subject.last_run_path).strip).to eq(JSON.pretty_generate(json))
  end

  context "reading" do
    context "but the last_run file does not exist" do
      before { File.delete(subject.last_run_path) if File.exist?(subject.last_run_path) }

      it "returns nil" do
        expect(subject.read).to be_nil
      end
    end

    context "a non empty result" do
      before { subject.write([]) }

      it "reads json from its last_run_path" do
        expect(subject.read).to eq(JSON.parse("[]"))
      end
    end

    context "an empty result" do
      before do
        File.open(subject.last_run_path, "w+") do |f|
          f.puts ""
        end
      end

      it "returns nil" do
        expect(subject.read).to be_nil
      end
    end
  end
end if SimpleCov.usable?

# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ViewCoverage do
  let(:root) { Dir.mktmpdir("view-coverage") }
  let(:rendered) { File.join(root, "app/views/foos/show.html.erb") }
  let(:unrendered) { File.join(root, "app/views/foos/index.html.erb") }
  let(:compiler) { SimpleCov::ViewCoverage::TemplateCompiler }

  before do
    FileUtils.mkdir_p(File.dirname(rendered))
    File.write(rendered, "<p><%= 1 %></p>\n")
    File.write(unrendered, "<p><%= 2 %></p>\n")

    allow(SimpleCov).to receive_messages(root: root, view_globs: ["app/views/**/*.erb"],
                                         view_coverage?: true, filters: [])
    # Whatever Coverage is holding for this suite is irrelevant here, and
    # peek_result copies all of it to answer.
    allow(Coverage).to receive_messages(running?: true, peek_result: {rendered => {lines: [1]}})
    allow(compiler).to receive_messages(available?: true, call: true)
  end

  after { FileUtils.rm_rf(root) }

  describe ".compile_unrendered" do
    it "compiles the templates the run never rendered" do
      expect(described_class.compile_unrendered).to eq([unrendered])
      expect(compiler).to have_received(:call).with(unrendered)
    end

    it "leaves the templates the run did render alone" do
      described_class.compile_unrendered

      expect(compiler).not_to have_received(:call).with(rendered)
    end

    it "omits templates the compiler refused" do
      allow(compiler).to receive(:call).and_return(false)

      expect(described_class.compile_unrendered).to be_empty
    end

    it "skips templates the report's own path filters exclude" do
      allow(SimpleCov).to receive(:filters).and_return([SimpleCov::StringFilter.new("app/views/foos")])

      expect(described_class.compile_unrendered).to be_empty
    end

    it "expands the globs against SimpleCov.root, not the working directory" do
      result = Dir.chdir(Dir.tmpdir) { described_class.compile_unrendered }

      expect(result).to eq([unrendered])
    end

    it "does nothing when the project didn't ask for view coverage" do
      allow(SimpleCov).to receive(:view_coverage?).and_return(false)

      expect(described_class.compile_unrendered).to be_empty
      expect(compiler).not_to have_received(:call)
    end

    it "does nothing once Coverage has stopped" do
      allow(Coverage).to receive(:running?).and_return(false)

      expect(described_class.compile_unrendered).to be_empty
    end

    it "does nothing without ActionView to compile with" do
      allow(compiler).to receive(:available?).and_return(false)

      expect(described_class.compile_unrendered).to be_empty
    end
  end
end

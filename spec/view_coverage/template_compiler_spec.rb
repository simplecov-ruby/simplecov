# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ViewCoverage::TemplateCompiler do
  # A stand-in for ActionView::Template: the only thing this asks of one is
  # that `compile` (which ActionView keeps private) defines the template's
  # method into the module it is handed.
  let(:template_class) do
    Class.new do
      attr_reader :compiled_into

      def compile(mod)
        @compiled_into = mod
      end
      private :compile
    end
  end
  let(:template) { template_class.new }
  let(:path) { "app/views/foos/show.html.erb" }

  describe ".available?" do
    it "is false in a project that doesn't load ActionView" do
      expect(described_class.available?).to be false
    end
  end

  describe ".format_for" do
    it "reads the format from the extension in front of the handler's" do
      expect(described_class.format_for("app/views/foos/show.html.erb")).to eq(:html)
    end

    it "reads formats other than html" do
      expect(described_class.format_for("app/views/foos/index.json.jbuilder")).to eq(:json)
    end

    it "is nil for a template named without a format" do
      expect(described_class.format_for("app/views/foos/show.erb")).to be_nil
    end
  end

  describe ".call" do
    before do
      allow(described_class).to receive(:build_template).and_return(template)
      allow(File).to receive(:binread).with(path).and_return("<p>hi</p>\n")
    end

    it "compiles the template into a throwaway module" do
      expect(described_class.call(path)).to be true
      expect(template.compiled_into).to be_a(Module)
    end

    it "passes the template's source to the builder" do
      described_class.call(path)

      expect(described_class).to have_received(:build_template).with(path, "<p>hi</p>\n")
    end

    it "reports the template and carries on when it doesn't compile" do
      allow(template).to receive(:compile).and_raise(ArgumentError, "broken")

      expect { expect(described_class.call(path)).to be false }
        .to output(/Skipping #{Regexp.escape(path)}, which did not compile \(ArgumentError\)/).to_stderr
    end

    it "survives a template that doesn't parse" do
      allow(template).to receive(:compile).and_raise(SyntaxError, "unexpected end")

      expect { expect(described_class.call(path)).to be false }.to output(/SyntaxError/).to_stderr
    end
  end
end

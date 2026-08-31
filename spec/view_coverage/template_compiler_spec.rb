# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ViewCoverage::TemplateCompiler do
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

  let(:handler) { Object.new }
  let(:handlers) { {"erb" => handler} }
  let(:built) { [] }
  let(:action_view_template) do
    registered = handlers
    recorded = built
    made = template
    Class.new do
      define_singleton_method(:registered_template_handler) { |extension| registered[extension] }
      define_singleton_method(:new) do |source, path, handler, locals:, format:|
        recorded << {source: source, path: path, handler: handler, locals: locals, format: format}
        made
      end
    end
  end

  describe ".available?" do
    it "is false in a project that doesn't load ActionView" do
      expect(described_class.available?).to be false
    end

    it "is true in a project that does" do
      stub_const("ActionView::Template", action_view_template)
      expect(described_class.available?).to be true
    end
  end

  describe ".build_template" do
    before { stub_const("ActionView::Template", action_view_template) }

    context "when nothing is registered for the extension" do
      let(:handlers) { {} }

      it "builds nothing, so a default glob naming a language the project lacks is skipped" do
        expect(described_class.build_template(path, "<p></p>")).to be_nil
      end
    end

    it "hands ActionView the source, the path, its handler and the format" do
      described_class.build_template(path, "<p></p>")

      expect(built.last).to eq(source: "<p></p>", path: path, handler: handler, locals: [], format: :html)
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

    it "ignores a dot in a directory along the way" do
      expect(described_class.format_for("app/v1.2/show.erb")).to be_nil
    end

    it "reads the format beside the handler, however many names precede it" do
      expect(described_class.format_for("app/views/show.v2.html.erb")).to eq(:html)
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

    it "skips a template language nothing is registered to handle" do
      allow(described_class).to receive(:build_template).and_return(nil)

      expect { expect(described_class.call(path)).to be false }.not_to output.to_stderr
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

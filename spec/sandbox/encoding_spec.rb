# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "source file encodings", :sandbox do
  before { setup_project("encodings") }

  let!(:result) { run_command_and_expect_success("bundle exec rspec spec") }
  let(:report_data) { html_report_data }

  def source_text(filename)
    report_data.fetch("coverage").fetch(filename).fetch("source").join("\n")
  end

  it "generates a report" do
    expect_coverage_report_generated(result)
  end

  it "totals the encoding fixtures" do
    expect(reported_total_percent(report_data)).to eq(55.55)
  end

  it "covers all four encoding fixtures" do
    expect(report_data.fetch("coverage").keys.length).to eq(4)
  end

  describe "a UTF-8 source" do
    let(:source) { source_text("lib/utf8.rb") }

    it "decodes legibly" do
      expect(source).not_to include("�")
    end

    it "keeps its emoji" do
      expect(source).to include("🇯🇵")
    end

    it "keeps its Japanese text" do
      expect(source).to include("おはよう")
    end
  end

  describe "a declared EUC-JP source" do
    let(:source) { source_text("lib/euc_jp.rb") }

    it "decodes legibly" do
      expect(source).not_to include("�")
    end

    it "keeps its Japanese text" do
      expect(source).to include("おはよう")
    end
  end

  describe "an undeclared EUC-JP source the tests loaded" do
    let(:source) { source_text("lib/euc_jp_not_declared.rb") }

    it "decodes legibly" do
      expect(source).not_to include("�")
    end

    it "keeps its ASCII text" do
      expect(source).to include("Fun3")
    end
  end

  describe "an undeclared EUC-JP source that was only tracked" do
    let(:source) { source_text("lib/euc_jp_not_declared_tracked.rb") }

    it "falls back to replacement characters" do
      expect(source).to include("�")
    end

    it "keeps its ASCII text" do
      expect(source).to include("NoDeclare")
    end
  end
end

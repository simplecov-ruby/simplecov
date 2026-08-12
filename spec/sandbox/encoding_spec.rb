# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# We've experienced some problems given source file encoding: make sure
# we try the appropriate encoding and the report data carries legible
# text. The cucumber feature checked the rendered detail views; the
# rendering is covered by the bun suite (html_frontend/test), so the
# same legibility assertions run against the embedded source data here.
RSpec.describe "source file encodings", :sandbox do
  before { setup_project("encodings") }

  def report_data
    @report_data ||= begin
      result = run_command_and_expect_success("bundle exec rspec spec")
      expect_coverage_report_generated(result)
      html_report_data
    end
  end

  def source_text(filename)
    report_data.fetch("coverage").fetch(filename).fetch("source").join("\n")
  end

  it "covers all four encoding fixtures" do
    expect(reported_total_percent(report_data)).to eq(55.55)
    expect(report_data.fetch("coverage").keys.length).to eq(4)
  end

  it "decodes UTF-8 and declared EUC-JP sources legibly" do
    utf8 = source_text("lib/utf8.rb")
    expect(utf8).not_to include("�")
    expect(utf8).to include("🇯🇵")
    expect(utf8).to include("おはよう")

    euc_jp = source_text("lib/euc_jp.rb")
    expect(euc_jp).not_to include("�")
    expect(euc_jp).to include("おはよう")
  end

  it "decodes an undeclared EUC-JP source that was loaded by the tests" do
    euc_jp_not_declared = source_text("lib/euc_jp_not_declared.rb")
    expect(euc_jp_not_declared).not_to include("�")
    expect(euc_jp_not_declared).to include("Fun3")
  end

  it "falls back to replacement characters for a tracked-only undeclared EUC-JP source" do
    # An EUC-JP file without a magic comment can't be decoded correctly
    # when it is only ever seen via cover — no way around it.
    tracked = source_text("lib/euc_jp_not_declared_tracked.rb")
    expect(tracked).to include("�")
    expect(tracked).to include("NoDeclare")
  end
end

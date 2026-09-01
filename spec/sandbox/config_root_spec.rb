# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "custom project root", :sandbox do
  before { setup_project("monorepo") }

  let(:data) { html_report_data }
  let(:file_percents) do
    data.fetch("coverage").transform_values do |file|
      displayed_percent(file.fetch("lines_covered_percent"))
    end
  end
  let!(:result) do
    install_dependencies
    write_file(".simplecov", <<~RUBY)
      SimpleCov.start do
        root __dir__
      end
    RUBY
    run_command_and_expect_success("bin/rspec_binstub_that_chdirs extra/spec/extra_spec.rb")
  end

  it "generates a report" do
    expect_coverage_report_generated(result)
  end

  it "keeps every file inside the configured root" do
    expect(data.fetch("coverage").keys.length).to eq(2)
  end

  it "covers all of them" do
    expect(displayed_percent(data.dig("total", "lines", "percent"))).to eq(100.00)
  end

  it "reports each of them relative to the configured root" do
    expect(file_percents).to eq(
      "base/lib/monorepo/base.rb" => 100.00,
      "extra/lib/monorepo/extra.rb" => 100.00
    )
  end
end

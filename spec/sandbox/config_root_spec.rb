# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# The root of the project can be customized; results are considered when
# they fall inside it even if the test process changes its working
# directory (the monorepo fixture's rspec binstub chdirs into a
# subproject before running).
RSpec.describe "custom project root", :sandbox do
  before { setup_project("monorepo") }

  it "keeps coverage results that fall inside the configured root" do
    install_dependencies
    write_file(".simplecov", "SimpleCov.root __dir__")

    result = run_command_and_expect_success("bin/rspec_binstub_that_chdirs extra/spec/extra_spec.rb")
    expect_coverage_report_generated(result)

    data = html_report_data
    expect(data.fetch("coverage").keys.length).to eq(2)
    expect(displayed_percent(data.dig("total", "lines", "percent"))).to eq(100.00)

    file_percents = data.fetch("coverage").transform_values do |file|
      displayed_percent(file.fetch("lines_covered_percent"))
    end
    expect(file_percents).to eq(
      "base/lib/monorepo/base.rb" => 100.00,
      "extra/lib/monorepo/extra.rb" => 100.00
    )
  end
end

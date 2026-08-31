# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "rspec-rails integration", :sandbox do
  before do
    setup_project("rails/rspec_rails")
    install_dependencies
  end

  def reported_groups(data)
    data.fetch("groups").to_h do |name, group|
      coverage = displayed_percent(group.fetch("lines").fetch("percent"))
      [name, {"coverage" => coverage, "files" => group.fetch("files").length}]
    end
  end

  it "produces a coverage report with the rails profile's groups" do
    result = run_command_and_expect_success("bundle exec rspec", timeout: 120)
    expect_coverage_report_generated(result)

    data = html_report_data
    expect(reported_total_percent(data)).to eq(50.00)
    expect(data.fetch("coverage").keys.length).to eq(5)

    expect(reported_groups(data)).to eq(
      "Controllers" => {"coverage" => 0.00, "files" => 1},
      "Channels" => {"coverage" => 100.00, "files" => 0},
      "Models" => {"coverage" => 60.00, "files" => 2},
      "Mailers" => {"coverage" => 100.00, "files" => 0},
      "Helpers" => {"coverage" => 100.00, "files" => 1},
      "Views" => {"coverage" => 100.00, "files" => 0},
      "Jobs" => {"coverage" => 0.00, "files" => 1},
      "Libraries" => {"coverage" => 100.00, "files" => 0}
    )
  end

  context "with cover_views" do
    before do
      write_file("spec/spec_helper.rb", <<~RUBY)
        require "simplecov"
        SimpleCov.start "rails" do
          cover_views
        end
      RUBY
    end

    def view_coverage(data)
      data.fetch("coverage").select { |path, _| path.end_with?(".erb") }
    end

    it "reports rendered and unrendered templates under the profile's Views group" do
      result = run_command_and_expect_success("bundle exec rspec", timeout: 120)
      expect_coverage_report_generated(result)

      data = html_report_data
      views = view_coverage(data)

      expect(views.keys).to contain_exactly(
        "app/views/foos/show.html.erb",
        "app/views/foos/orphan.html.erb",
        "app/views/layouts/application.html.erb"
      )
      expect(views.fetch("app/views/foos/show.html.erb").fetch("lines")).to eq([1, 1, 0, nil])
      expect(views.fetch("app/views/foos/orphan.html.erb").fetch("lines")).to eq([0])
      expect(views.fetch("app/views/layouts/application.html.erb").fetch("lines")).to all(satisfy do |hits|
        hits.nil? || hits.zero?
      end)

      expect(reported_groups(data).fetch("Views")).to eq("coverage" => 22.22, "files" => 3)
    end
  end
end

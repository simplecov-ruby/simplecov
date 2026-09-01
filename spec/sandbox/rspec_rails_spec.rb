# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "rspec-rails integration", :sandbox do
  before do
    setup_project("rails/rspec_rails")
    install_dependencies
  end

  let(:data) { html_report_data }

  def reported_groups(data)
    data.fetch("groups").to_h do |name, group|
      coverage = displayed_percent(group.fetch("lines").fetch("percent"))
      [name, {"coverage" => coverage, "files" => group.fetch("files").length}]
    end
  end

  describe "the rails profile" do
    let!(:result) { run_command_and_expect_success("bundle exec rspec", timeout: 120) }
    let(:expected_groups) do
      {
        "Controllers" => {"coverage" => 0.00, "files" => 1},
        "Channels" => {"coverage" => 100.00, "files" => 0},
        "Models" => {"coverage" => 60.00, "files" => 2},
        "Mailers" => {"coverage" => 100.00, "files" => 0},
        "Helpers" => {"coverage" => 100.00, "files" => 1},
        "Views" => {"coverage" => 100.00, "files" => 0},
        "Jobs" => {"coverage" => 0.00, "files" => 1},
        "Libraries" => {"coverage" => 100.00, "files" => 0}
      }
    end

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "totals the coverage" do
      expect(reported_total_percent(data)).to eq(50.00)
    end

    it "covers the app's files" do
      expect(data.fetch("coverage").keys.length).to eq(5)
    end

    it "buckets them into the profile's groups" do
      expect(reported_groups(data)).to eq(expected_groups)
    end
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

    let!(:result) { run_command_and_expect_success("bundle exec rspec", timeout: 120) }
    let(:views) { data.fetch("coverage").select { |path, _| path.end_with?(".erb") } }

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "reports every template" do
      expect(views.keys).to contain_exactly(
        "app/views/foos/show.html.erb",
        "app/views/foos/orphan.html.erb",
        "app/views/layouts/application.html.erb"
      )
    end

    it "records hits against a rendered template's own lines" do
      expect(views.fetch("app/views/foos/show.html.erb").fetch("lines")).to eq([1, 1, 0, nil])
    end

    it "reports an unrendered template at 0%" do
      expect(views.fetch("app/views/foos/orphan.html.erb").fetch("lines")).to eq([0])
    end

    it "records no hits against the layout" do
      expect(views.fetch("app/views/layouts/application.html.erb").fetch("lines"))
        .to all(satisfy { |hits| hits.nil? || hits.zero? })
    end

    it "puts the templates in the profile's Views group" do
      expect(reported_groups(data).fetch("Views")).to eq("coverage" => 22.22, "files" => 3)
    end
  end
end

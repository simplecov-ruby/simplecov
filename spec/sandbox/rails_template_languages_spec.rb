# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

# `cover_views` reaches any template language the project has registered an
# ActionView handler for, not just ERB. Haml and Slim generate Ruby that keeps
# the template's own line structure, so eval coverage lands on the source
# lines the author wrote, with no mapping on SimpleCov's side.
RSpec.describe "template language integration", :sandbox do
  before do
    setup_project("rails/rspec_rails")
    # Haml and Slim run here and nowhere else, so the fixture keeps them in an
    # optional Gemfile group that only this spec asks for.
    self.bundle_with = "templates"
    install_dependencies

    write_file("spec/spec_helper.rb", <<~RUBY)
      require "simplecov"
      SimpleCov.start "rails" do
        cover_views
      end
    RUBY
    write_file("app/views/pages/page.html.#{language}", rendered_template)
    write_file("app/views/pages/orphan.html.#{language}", orphan_template)
    write_file("spec/views/pages_spec.rb", <<~RUBY)
      require "rails_helper"

      RSpec.describe "pages", type: :view do
        it "renders the page" do
          assign(:foo, Foo.new)
          assign(:admin, false)
          assign(:items, %w[a b])

          render template: "pages/page"

          expect(rendered).to include("bar")
        end
      end
    RUBY
  end

  def template_coverage
    html_report_data.fetch("coverage").select { |path, _| path.start_with?("app/views/pages/") }
  end

  # Both languages get the same page: an output line, a conditional whose body
  # this run doesn't reach, and a loop whose body it reaches twice. One child
  # run answers for both templates: a rails boot per assertion is what made
  # these examples the slowest in the suite.
  shared_examples "a template language" do
    it "records hits against the template's own lines and reports an unrendered template at 0%" do
      result = run_command_and_expect_success("bundle exec rspec", timeout: 120)
      expect_coverage_report_generated(result)

      expect(template_coverage.fetch("app/views/pages/page.html.#{language}").fetch("lines"))
        .to eq([1, 1, 0, 1, 1, 2])
      expect(template_coverage.fetch("app/views/pages/orphan.html.#{language}").fetch("lines")).to eq([0])
    end
  end

  context "with haml" do
    let(:language) { "haml" }
    let(:rendered_template) do
      <<~HAML
        %h1= @foo.bar
        - if @admin
          %p Only an admin sees this.
        %ul
          - @items.each do |item|
            %li= item
      HAML
    end
    let(:orphan_template) { "%p No spec renders this template.\n" }

    it_behaves_like "a template language"
  end

  context "with slim" do
    let(:language) { "slim" }
    let(:rendered_template) do
      <<~SLIM
        h1 = @foo.bar
        - if @admin
          p Only an admin sees this.
        ul
          - @items.each do |item|
            li = item
      SLIM
    end
    let(:orphan_template) { "p No spec renders this template.\n" }

    it_behaves_like "a template language"
  end

  # A default `cover_views` glob names `.haml` and `.slim` in every project,
  # including the ones that have neither. ActionView answers an unregistered
  # extension with its raw handler, which would compile the file as a lump of
  # static text and report it as an untested view.
  context "without the template gems installed" do
    let(:language) { "haml" }
    let(:rendered_template) { "%p Never compiled.\n" }
    let(:orphan_template) { "%p Nor this.\n" }

    before do
      self.bundle_with = nil
      write_file("spec/views/pages_spec.rb", "")
    end

    it "leaves templates it has no handler for out of the report" do
      run_command_and_expect_success("bundle exec rspec", timeout: 120)

      expect(template_coverage).to be_empty
    end
  end
end

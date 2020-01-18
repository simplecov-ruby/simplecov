# frozen_string_literal: true

# While you're here, handy tip for debugging: try to attach @announce-output
# @announce-command to the scenarios/features to see what's going on

require "bundler"
Bundler.setup
require "aruba/cucumber"
require "aruba/config/jruby" if RUBY_ENGINE == "jruby"
require "capybara/cucumber"
require "capybara/apparition"
require "simplecov"

# Fake rack app for capybara that just returns the latest coverage report from aruba temp project dir
Capybara.app = lambda { |env|
  request_path = env["REQUEST_PATH"] || "/"
  request_path = "/index.html" if request_path == "/"
  corresponding_file_path =
    File.join(File.dirname(__FILE__), "../../tmp/aruba/project/coverage", request_path)

  content =
    if File.exist?(corresponding_file_path)
      File.read(corresponding_file_path)
    else
      # See #776 for whatever reason sometimes JRuby in one feature couldn't
      # find the loading.gif - which isn't essential so answering empty string
      # should be good enough
      warn "Couldn't find #{corresponding_file_path} generating empty response"
      ""
    end

  [
    200,
    {"Content-Type" => "text/html"},
    [content]
  ]
}

Capybara.configure do |config|
  config.ignore_hidden_elements = false
  config.server = :webrick
  config.default_driver = :apparition
end

Before("@branch_coverage") do
  skip_this_scenario unless SimpleCov.branch_coverage_supported?
end

Before("@parallel_tests_project") do
  @test_project_name = "parallel_tests_project"
end

Before("@old_coverage_json") do
  @test_project_name = "old_coverage_json"
end

Before do
  this_dir = File.dirname(__FILE__)

  @test_project_name ||= "faked_project"

  # Clean up and create blank state for fake project
  cd(".") do
    FileUtils.rm_rf "project"
    FileUtils.cp_r File.join(this_dir, "../../test_projects/#{@test_project_name}/"), "project"
  end

  step 'I cd to "project"'
end

Aruba.configure do |config|
  config.allow_absolute_paths = true

  # JRuby needs a bit longer to get going
  config.exit_timeout = RUBY_ENGINE == "jruby" ? 60 : 20
end

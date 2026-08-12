# frozen_string_literal: true

require_relative "../support/source_generator"

StorefrontFixture::SourceGenerator.call

require "simplecov"

project_root = File.expand_path("..", __dir__)

SimpleCov.start "rails" do
  root project_root
  project_name "Storefront"
  command_name "Screenshot specs"
  enable_coverage :branch
  enable_coverage :method
end

StorefrontFixture::REQUIRED_PATHS.each do |path|
  require File.join(project_root, path)
end

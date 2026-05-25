# frozen_string_literal: true

SimpleCov.profiles.define "bundler_filter" do
  skip "/vendor/bundle/"
end

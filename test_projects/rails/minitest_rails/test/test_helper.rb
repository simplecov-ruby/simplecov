# frozen_string_literal: true

require "simplecov"
SimpleCov.start "rails"

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/parallel_worker_probe"
ParallelWorkerProbe.reset!

class ActiveSupport::TestCase
  parallelize workers: 2, threshold: 0, parallelize_databases: false
  include ParallelWorkerProbe
end

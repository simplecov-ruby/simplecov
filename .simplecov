# frozen_string_literal: true

# Loaded by the bundled `simplecov` CLI to discover where this
# project's dogfood report lives. Guarded on SIMPLECOV_CLI so the
# value doesn't leak into descendant Ruby processes (the eval_test
# fixture, the cucumber test_projects, etc.) when their own
# `require "simplecov"` walks up the directory tree and incidentally
# finds this file.
SimpleCov.coverage_dir "tmp/dogfood" if ENV["SIMPLECOV_CLI"]

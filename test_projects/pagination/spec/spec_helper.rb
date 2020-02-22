# frozen_string_literal: true

require "simplecov"

SimpleCov.start

Dir["lib/*.rb"].each {|file| require_relative "../#{file}" }

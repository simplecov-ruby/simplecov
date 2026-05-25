# frozen_string_literal: true

SimpleCov.profiles.define "hidden_filter" do
  skip(/\A\..*/)
end

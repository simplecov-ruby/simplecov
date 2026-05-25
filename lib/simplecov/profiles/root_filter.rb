# frozen_string_literal: true

SimpleCov.profiles.define "root_filter" do
  # Exclude all files outside of simplecov root. Shares the regex with
  # SimpleCov::UselessResultsRemover so the root-prefix logic lives in one
  # place; this profile is the user-facing entry point that tools like
  # `SimpleCov.filtered` apply.
  skip do |src|
    src.filename !~ SimpleCov::UselessResultsRemover.root_regx
  end
end

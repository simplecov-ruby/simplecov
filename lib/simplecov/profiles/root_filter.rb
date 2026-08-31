# frozen_string_literal: true

SimpleCov.profiles.define "root_filter" do
  skip do |src|
    src.filename !~ SimpleCov::UselessResultsRemover.root_regex
  end
end

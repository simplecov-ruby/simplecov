require "simplecov"

SimpleCov.enable_coverage :branch
SimpleCov.start "rails" do
  # Brings the templates under app/views into the report: the ones the
  # specs render are measured through eval coverage, and the ones no spec
  # renders are compiled at the end of the run so they appear at 0%.
  cover_views
end

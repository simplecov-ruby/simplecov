# frozen_string_literal: true

SimpleCov.profiles.define "rails" do
  load_profile "test_frameworks"

  skip %r{\Aconfig/}
  skip %r{\Adb/}

  group "Controllers", "app/controllers"
  group "Channels", "app/channels"
  group "Models", "app/models"
  group "Mailers", "app/mailers"
  group "Helpers", "app/helpers"
  group "Jobs", %w[app/jobs app/workers]
  group "Libraries", "lib/"

  # Preserve the legacy `track_files` semantics (additive disk-discovery
  # without restricting the report's universe): write the ivar directly
  # so loading the profile doesn't emit the public-API deprecation. Users
  # migrating their own configs should prefer `cover "{app,lib}/**/*.rb"`,
  # which both injects unloaded files and scopes the report to the match
  # set — usually the intended behavior for a Rails project.
  @tracked_files = "{app,lib}/**/*.rb"

  # `parallelize(workers: ...)` forks worker processes that each run a
  # slice of the suite. Without subprocess support, the workers' coverage
  # is dropped on the floor and the parent records 0% for everything they
  # touched. Hooking `Process._fork` makes each worker re-call
  # `SimpleCov.start` with a unique command_name so the resultsets merge
  # correctly.
  merge_subprocesses true
end

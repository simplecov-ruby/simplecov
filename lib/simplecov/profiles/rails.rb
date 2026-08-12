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

  # Additive disk-discovery without restricting the report's universe:
  # write the ivar directly, since `cover "{app,lib}/**/*.rb"` would also
  # scope the report to that match set and drop everything else a Rails
  # app happens to load. Users who want that scoping should say `cover`
  # in their own config.
  @tracked_files = "{app,lib}/**/*.rb"

  # `parallelize(workers: ...)` forks worker processes that each run a
  # slice of the suite. Without subprocess support, the workers' coverage
  # is dropped on the floor and the parent records 0% for everything they
  # touched. Hooking `Process._fork` makes each worker re-call
  # `SimpleCov.start` with a unique command_name so the resultsets merge
  # correctly.
  merge_subprocesses true
end

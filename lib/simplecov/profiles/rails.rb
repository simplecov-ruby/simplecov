# frozen_string_literal: true

SimpleCov.profiles.define "rails" do
  load_profile "test_frameworks"

  add_filter %r{\Aconfig/}
  add_filter %r{\Adb/}

  add_group "Controllers", "app/controllers"
  add_group "Channels", "app/channels"
  add_group "Models", "app/models"
  add_group "Mailers", "app/mailers"
  add_group "Helpers", "app/helpers"
  add_group "Jobs", %w[app/jobs app/workers]
  add_group "Libraries", "lib/"

  track_files "{app,lib}/**/*.rb"

  # `parallelize(workers: ...)` forks worker processes that each run a
  # slice of the suite. Without subprocess support, the workers' coverage
  # is dropped on the floor and the parent records 0% for everything they
  # touched. Hooking `Process._fork` makes each worker re-call
  # `SimpleCov.start` with a unique command_name so the resultsets merge
  # correctly.
  enable_for_subprocesses true
end

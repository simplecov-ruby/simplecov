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
  group "Views", "app/views"
  group "Jobs", %w[app/jobs app/workers]
  group "Libraries", "lib/"

  @tracked_files = "{app,lib}/**/*.rb"

  merge_subprocesses true
end

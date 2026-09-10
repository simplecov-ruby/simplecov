# frozen_string_literal: true

SimpleCov.profiles.define "rails" do
  load_profile "test_frameworks"

  skip %r{\Aconfig/}
  skip %r{\Adb/}

  group "Channels", "app/channels"
  group "Controllers", "app/controllers"
  group "Helpers", "app/helpers"
  group "Jobs", %w[app/jobs app/workers]
  group "Libraries", "lib/"
  group "Mailers", "app/mailers"
  group "Models", "app/models"
  group "Views", "app/views"

  @tracked_files = "{app,lib}/**/*.rb"

  merge_subprocesses true
end

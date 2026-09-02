# frozen_string_literal: true

# Cuts one release's section out of CHANGELOG.md, for the GitHub Release the
# Push Gem workflow opens on a tag push. A release heading is the version and
# its date underlined with equals signs, so a version's section runs from its
# heading to the next one.
module ReleaseNotes
  extend self

  HEADING = /^(?=\S+ \(\d{4}-\d{2}-\d{2}\)\n=+$)/

  def for(version, changelog = File.read(File.expand_path("../CHANGELOG.md", __dir__)))
    section = changelog.split(HEADING).find { |candidate| candidate.start_with?("#{version} (") }
    raise ArgumentError, "CHANGELOG.md has no #{version} section" unless section

    "#{section.lines.drop(2).join.strip}\n"
  end
end

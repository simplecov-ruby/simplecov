# frozen_string_literal: true

# Cuts one release's section out of CHANGELOG.md, for the GitHub Release the
# Push Gem workflow opens on a tag push. A release heading is a level-two
# heading naming the version and its date (`## [1.2.0] - 2026-09-04`), so a
# version's section runs from its heading to the next one. The changelog
# collects its links as reference definitions at the bottom of the file, so
# the definitions the section uses are carried along with it.
module ReleaseNotes
  extend self

  HEADING = /^(?=## )/
  DEFINITION = /^\[([^\]]+)\]: (\S+)$/

  def for(version, changelog = File.read(File.expand_path("../CHANGELOG.md", __dir__)))
    section = changelog.split(HEADING).find { |candidate| candidate.match?(/\A## \[?#{Regexp.escape(version)}\]? - /) }
    raise ArgumentError, "CHANGELOG.md has no #{version} section" unless section

    body = section.lines.drop(1).take_while { |line| !line.match?(DEFINITION) }.join.strip
    "#{[body, *definitions_used(body, changelog)].join("\n\n")}\n"
  end

  private

  def definitions_used(body, changelog)
    definitions = changelog.scan(DEFINITION).to_h
    labels = body.scan(/\[([^\]]+)\](?![(\[:])/).flatten.uniq.select { |label| definitions.key?(label) }
    return [] if labels.empty?

    [labels.map { |label| "[#{label}]: #{definitions[label]}" }.join("\n")]
  end
end

# frozen_string_literal: true

require "fileutils"

require_relative "coverage_cases"

module StorefrontFixture
  module SourceGenerator
    # The only contents of these trees are the files generated below, which
    # is why .gitignore lists both. Clearing them is what makes a re-run a
    # true refresh: a renamed or deleted entry leaves nothing behind for the
    # rails profile, which tracks files from disk, to report back at 0% and
    # fail the verification with a confusing file count.
    GENERATED_TREES = %w[app lib].freeze

    module_function

    def call
      stray = FILES.reject { |entry| GENERATED_TREES.include?(entry.path.split("/").first) }
      raise "Fixture files live in #{GENERATED_TREES.join(' and ')}: #{stray.map(&:path).join(', ')}" if stray.any?

      GENERATED_TREES.each { |tree| FileUtils.rm_rf(File.join(project_root, tree)) }

      FILES.each do |entry|
        destination = File.join(project_root, entry.path)
        FileUtils.mkdir_p(File.dirname(destination))
        File.write(destination, entry.source)
      end
    end

    def project_root
      File.expand_path("..", __dir__)
    end
  end
end

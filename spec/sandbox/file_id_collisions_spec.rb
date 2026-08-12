# frozen_string_literal: true

require "digest"
require "helper"
require "support/sandbox_project"

# The viewer derives per-file HTML ids from SHA-1 digests truncated to
# 8 hex characters, so distinct files can collide. These two fixture
# filenames really do collide (both truncate to c561e6d5); the report
# data must carry both files as separate entries so the viewer's
# collision-resolving id allocator can give each source link its own
# detailed view. The allocator itself, and opening both views, is
# covered by the bun suite (html_frontend/test/format.test.ts uses its
# own brute-forced collision pair; dialog navigation lives in
# html_frontend/test/dialog.test.ts).
RSpec.describe "source files with colliding hashes", :sandbox do
  before do
    setup_project("faked_project")

    configure_simplecov(:rspec, <<~RUBY)
      require 'simplecov'
      SimpleCov.start
    RUBY

    write_file("lib/file_46276.rb", <<~RUBY)
      module File46276
        VALUE = 46_276
      end
    RUBY

    write_file("lib/file_56865.rb", <<~RUBY)
      module File56865
        VALUE = 56_865
      end
    RUBY

    write_file("spec/file_id_collisions_spec.rb", <<~RUBY)
      require 'spec_helper'
      require_relative '../lib/file_46276'
      require_relative '../lib/file_56865'

      RSpec.describe 'source files with colliding hashes' do
        it 'loads both files' do
          expect(File46276::VALUE + File56865::VALUE).to eq(103_141)
        end
      end
    RUBY
  end

  it "reports both colliding files as distinct entries" do
    # Guard the fixture's reason for being: if either name stops
    # colliding, this spec would silently stop exercising the case.
    expect(Digest::SHA1.hexdigest("lib/file_46276.rb")[0, 8])
      .to eq(Digest::SHA1.hexdigest("lib/file_56865.rb")[0, 8])

    result = run_command_and_expect_success("bundle exec rspec spec/file_id_collisions_spec.rb")
    expect_coverage_report_generated(result)

    coverage = html_report_data.fetch("coverage")
    expect(coverage.keys).to include("lib/file_46276.rb", "lib/file_56865.rb")
    expect(coverage.fetch("lib/file_46276.rb").fetch("lines_covered_percent")).to eq(100.0)
    expect(coverage.fetch("lib/file_56865.rb").fetch("lines_covered_percent")).to eq(100.0)
    # Each entry embeds its own source, so the two detailed views cannot
    # fall back to showing the same file.
    expect(coverage.fetch("lib/file_46276.rb").fetch("source").join).to include("File46276")
    expect(coverage.fetch("lib/file_56865.rb").fetch("source").join).to include("File56865")
  end
end

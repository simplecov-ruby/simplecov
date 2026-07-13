# frozen_string_literal: true

require "rubygems"
require "bundler/setup"
Bundler::GemHelper.install_tasks

# `rake release` builds the gem and pushes the version tag, but it does not
# push the gem itself. Pushing the tag triggers the "Push Gem" GitHub Actions
# workflow (.github/workflows/push_gem.yml), which publishes to RubyGems via
# trusted publishing (no API key, no OTP) and opens the GitHub Release. Dropping
# the local `release:rubygem_push` step is what keeps the OTP prompt away.
Rake::Task["release"].clear
desc "Build the gem and push the version tag (CI publishes on the tag push)"
task release: %w[build release:guard_clean release:source_control_push]

# See https://github.com/simplecov-ruby/simplecov/issues/171
desc "Set permissions on all files so they are compatible with both user-local and system-wide installs"
task :fix_permissions do
  system 'bash -c "find lib/ -type f -exec chmod 644 {} \; && find . -type d -exec chmod 755 {} \;"'
end
# Enforce proper permissions on each build
Rake::Task[:build].prerequisites.unshift :fix_permissions

require "rspec/core/rake_task"
RSpec::Core::RakeTask.new(:spec)

begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new
rescue LoadError
  task :rubocop do
    warn "Rubocop is disabled"
  end
end

begin
  require "cucumber/rake/task"
  Cucumber::Rake::Task.new do |t|
    t.cucumber_opts = %w[--retry 3 --no-strict-flaky]
  end
rescue LoadError
  # Cucumber isn't installed (e.g. on JRuby, which only runs `rake spec`).
  task :cucumber do
    warn "Cucumber is disabled"
  end
end

desc "Validate the RBS type signatures in sig/"
task :rbs do
  require "rbs"
  sh "rbs", "-r", "forwardable", "-r", "prism", "-r", "socket", "-I", "sig", "validate"
rescue LoadError
  # RBS's native extension doesn't build on JRuby; see the Gemfile.
  warn "RBS is disabled"
end

desc "Type-check lib/ against sig/ with Steep (strict mode)"
task :steep do
  require "rbs"
  sh "steep", "check"
rescue LoadError
  # Steep depends on RBS, which doesn't build on JRuby; see the Gemfile.
  warn "Steep is disabled"
end

task test: %i[spec cucumber]
task default: %i[rubocop rbs steep spec cucumber]

namespace :assets do
  desc "Compile frontend assets (HTML, JS, CSS) using esbuild"
  task :compile do
    frontend = File.expand_path("html_frontend", __dir__)
    outdir = File.expand_path("lib/simplecov/formatter/html_formatter/public", __dir__)

    puts "Compiling assets..."

    # JS: esbuild bundles TypeScript + highlight.js and minifies
    sh "cd #{frontend} && esbuild src/app.ts --bundle --minify --target=es2015 --outfile=#{outdir}/application.js"

    # CSS: concatenate in order and minify
    css = %w[
      assets/stylesheets/reset.css
      assets/stylesheets/plugins/highlight.css
      assets/stylesheets/screen.css
    ].map { |f| File.read(File.join(frontend, f)) }.join("\n")

    IO.popen(%w[esbuild --minify --loader=css], "r+") do |io|
      io.write(css)
      io.close_write
      File.write("#{outdir}/application.css", io.read)
    end

    # HTML: copy static index.html
    FileUtils.cp(File.join(frontend, "src/index.html"), File.join(outdir, "index.html"))
  end
end

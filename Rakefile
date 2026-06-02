# frozen_string_literal: true

require "rubygems"
require "bundler/setup"
Bundler::GemHelper.install_tasks

# SimpleCov is published by the "Push Gem" GitHub Actions workflow
# (.github/workflows/push_gem.yml) using RubyGems trusted publishing: CI runs
# `rake release` with a short-lived OIDC token, so there is no API key and no
# OTP prompt. Running `rake release` from a developer machine would instead tag,
# push, and upload the gem from here (hence the OTP prompt), so outside CI we
# replace the task with a pointer to the workflow. GitHub Actions sets CI=true,
# so the real release task still runs there untouched.
unless ENV["CI"]
  Rake::Task["release"].clear
  desc "Publish a release (handled by the Push Gem workflow in CI)"
  task :release do
    abort <<~MESSAGE
      SimpleCov releases are published by the "Push Gem" GitHub Actions
      workflow, not from a local machine, so there is no OTP prompt.

      To cut a release:
        1. Bump SimpleCov::VERSION and update CHANGELOG.md, then merge to main.
        2. Run the "Push Gem" workflow from the Actions tab. CI tags the
           version and publishes to RubyGems.org via trusted publishing.

      To build the gem locally without publishing, run `rake build`.
    MESSAGE
  end
end

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

require "cucumber/rake/task"
Cucumber::Rake::Task.new do |t|
  t.cucumber_opts = %w[--retry 3 --no-strict-flaky]
end

task test: %i[spec cucumber]
task default: %i[rubocop spec cucumber]

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

# frozen_string_literal: true

require "rubygems"
require "bundler/setup"
Bundler::GemHelper.install_tasks

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

require "rake/testtask"
Rake::TestTask.new(:test_html) do |t|
  t.libs << "test/html_formatter"
  t.pattern = "test/html_formatter/**/test_*.rb"
  t.verbose = true
end

task test: %i[spec cucumber test_html]
task default: %i[rubocop spec cucumber test_html]

namespace :assets do
  desc "Compile frontend assets (JS + CSS) using esbuild"
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
  end
end

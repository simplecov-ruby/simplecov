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
  # The serial task stays around for debugging a single flow without
  # worker interleaving.
  Cucumber::Rake::Task.new(:"cucumber:serial")
rescue LoadError
  # Cucumber isn't installed (e.g. on JRuby, which only runs `rake spec`).
end

# The suite's cost is almost entirely subprocess and browser wall clock,
# so it parallelizes nearly linearly: `parallel_cucumber` splits the
# feature files across CPU-count workers, each in its own Aruba sandbox
# (see features/support/env.rb).
desc "Run Cucumber features across parallel workers"
task :cucumber do
  if Rake::Task.task_defined?(:"cucumber:serial")
    sh "bundle exec parallel_cucumber --serialize-stdout features"
  else
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

# JS: esbuild bundles TypeScript + highlight.js and minifies
def compile_frontend_js(frontend)
  require "tmpdir"
  Dir.mktmpdir do |tmp|
    esbuild = "esbuild src/app.ts --bundle --minify --target=es2015"
    sh "cd #{frontend} && #{esbuild} --outfile=#{tmp}/application.js"
    File.read(File.join(tmp, "application.js"))
  end
end

# CSS: concatenate in order and minify
def compile_frontend_css(frontend)
  css = %w[
    assets/stylesheets/reset.css
    assets/stylesheets/plugins/highlight.css
    assets/stylesheets/screen.css
  ].map { |f| File.read(File.join(frontend, f)) }.join("\n")

  mangle_css_custom_properties(minify_css(css))
end

def minify_css(css)
  IO.popen(%w[esbuild --minify --loader=css], "r+") do |io|
    io.write(css)
    io.close_write
    io.read
  end
end

# Custom properties that JavaScript reads or writes by name and must
# therefore survive mangling. Any `setProperty`/`getPropertyValue` call
# added to html_frontend/src must have its property listed here.
# bar_width.ts sets --bar-sizer-width; page.ts reads the band colours
# to draw the favicon.
JS_VISIBLE_CSS_VARS = %w[--bar-sizer-width --green --red --yellow].freeze

# The stylesheets lean on descriptively named custom properties
# (--covered-line-num-bg and friends), and every use repeats the full
# name, so the names alone cost ~4KB after minification. They are
# internal to the compiled template, so rename them to short aliases,
# most frequent first. The single gsub applies the whole mapping in one
# pass over full `--name` tokens, so `--text` cannot clobber
# `--text-secondary` and renames cannot chain.
def mangle_css_custom_properties(css)
  token = /--[a-zA-Z][\w-]*/
  counts = css.scan(token).tally.except(*JS_VISIBLE_CSS_VARS)
  aliases = short_css_names.reject { |name| counts.key?(name) }
  mapping = counts.sort_by { |name, count| [-count, name] }.map(&:first).zip(aliases).to_h
  css.gsub(token) { |name| mapping.fetch(name, name) }
end

# --a, --b, ... --z, --aa, --ab, ... (702 names for 64 properties today)
def short_css_names
  letters = ("a".."z").to_a
  letters.map { |a| "--#{a}" } + letters.product(letters).map { |a, b| "--#{a}#{b}" }
end

# The bundles land inside <script>/<style> elements, where the HTML parser
# treats these sequences as element terminators (or, for "<!--"/"<script",
# as entry into the script-data-escaped states). The current bundles
# contain none of them; refuse to build one that does rather than emit a
# template that truncates at render time.
def assert_inline_safe(bundle, label, sequences)
  sequences.each do |sequence|
    next unless bundle.downcase.include?(sequence)

    raise "Compiled #{label} contains #{sequence.inspect} and cannot be inlined safely"
  end
end

namespace :assets do
  desc "Compile the frontend into a single self-contained index.html template"
  task :compile do
    frontend = File.expand_path("html_frontend", __dir__)
    outdir = File.expand_path("lib/simplecov/formatter/html_formatter/public", __dir__)

    puts "Compiling assets..."

    js = compile_frontend_js(frontend)
    css = compile_frontend_css(frontend)
    assert_inline_safe(js, "JS", %w[</script <script <!--])
    assert_inline_safe(css, "CSS", %w[</style])

    # HTML: inline the bundles into the template, leaving the coverage
    # data marker for HTMLFormatter to substitute at report time.
    html = File.read(File.join(frontend, "src/index.html"))
    {
      "<!-- SIMPLECOV_CSS -->" => "<style>#{css}</style>",
      "<!-- SIMPLECOV_APP_JS -->" => "<script>#{js}</script>"
    }.each do |marker, replacement|
      html.sub!(marker) { replacement } || raise("Marker #{marker.inspect} not found in src/index.html")
    end
    File.write(File.join(outdir, "index.html"), html)
  end
end

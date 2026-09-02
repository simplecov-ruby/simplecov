# frozen_string_literal: true

require "rubygems"
require "bundler/setup"
require "open3"
require "shellwords"
Bundler::GemHelper.install_tasks

Rake::Task["release"].clear
desc "Build the gem and push the version tag (CI publishes on the tag push)"
# `rake release` builds the gem and pushes the version tag but not the gem
# itself. Pushing the tag triggers the "Push Gem" workflow, which publishes to
# RubyGems via trusted publishing (no API key, no OTP). Dropping the local
# `release:rubygem_push` step is what keeps the OTP prompt away.
# See https://github.com/simplecov-ruby/simplecov/issues/171
task release: %w[build release:guard_clean release:source_control_push]

desc "Set permissions on all files so they are compatible with both user-local and system-wide installs"
task :fix_permissions do
  system 'bash -c "find lib/ -type f -exec chmod 644 {} \; && find . -type d -exec chmod 755 {} \;"'
end
Rake::Task[:build].prerequisites.unshift :fix_permissions

require "rspec/core/rake_task"
RSpec::Core::RakeTask.new(:"spec:serial")

RUNTIME_LOG = "tmp/parallel_runtime_rspec.log"
RUNTIME_PARTIALS = "tmp/parallel_runtime"

desc "Run the RSpec suite across parallel workers"
# Splitting by runtime matters here: the sandbox spec files are tiny on disk
# but each spends seconds driving fixture subprocesses, so the default
# file-size split parks them on a couple of workers. RuntimeLogFormatter in
# .rspec_parallel records per-file runtimes during every parallel run, one file
# per worker, and the merge below collects them.
task :spec do
  require "parallel_tests"
  rm_rf "tmp/dogfood-partials"
  rm_rf RUNTIME_PARTIALS
  sh "bundle exec parallel_rspec --serialize-stdout #{runtime_grouping}spec"
  merge_runtime_log
rescue LoadError
  Rake::Task[:"spec:serial"].invoke
end

# A log written against a different set of spec files groups everything it does
# not recognise onto one worker, which is slower than not grouping at all. The
# first run has no log, and --allowed-missing 100 lets a handful of new or
# renamed files through, but a log whose paths have largely stopped existing
# describes some other tree and is thrown away.
def runtime_grouping
  return "" unless File.size?(RUNTIME_LOG)

  logged = File.readlines(RUNTIME_LOG).filter_map { |line| line[/\A(.+):[\d.]+$/, 1] }
  return "" if logged.empty? || logged.count { |file| File.exist?(file) } < logged.size * 0.9

  "--group-by runtime --allowed-missing 100 "
end

# Only after a run that finished, so a suite that died halfway cannot replace a
# whole log with its fragment.
def merge_runtime_log
  partials = FileList["#{RUNTIME_PARTIALS}/*.log"]
  return if partials.empty?

  File.write(RUNTIME_LOG, partials.sort.flat_map { |partial| File.readlines(partial) }.join)
end

# RuboCop runs in its own process. Standard's rake task runs in this one and
# registers the Capybara, FactoryBot and RSpecRails cops its plugin loads, and
# an in-process RuboCop run that follows it would execute those cops without
# the configuration their plugins carry, which crashes every one of them.
desc "Lint with RuboCop"
task :rubocop do
  require "rubocop"
  sh "rubocop"
rescue LoadError
  warn "RuboCop is disabled"
end

begin
  require "standard/rake"
rescue LoadError
  task :standard do
    warn "Standard is disabled"
  end
end

desc "Regenerate man/simplecov.1 from the usage document"
task :man do
  require_relative "tasks/man_page"
  mkdir_p "man"
  File.write("man/simplecov.1", ManPage.build)
end

namespace :release do
  desc "Print one release's CHANGELOG.md section as GitHub Release notes (VERSION defaults to the gem's)"
  task :notes, [:version] do |_task, args|
    require_relative "tasks/release_notes"
    require "simplecov/version"
    puts ReleaseNotes.for(args[:version] || SimpleCov::VERSION)
  end
end

desc "Mutation-test the whole lib with mutant (slow)"
task :mutant do
  sh "bundle exec mutant run"
end

namespace :mutant do
  desc "Mutation-test only the subjects touched since REF (default origin/main)"
  task :since, [:ref] do |_task, args|
    sh "bundle exec mutant run --since #{args[:ref] || "origin/main"}"
  end

  desc "List the subjects touched since REF, one per line"
  task :subjects, [:ref] do |_task, args|
    require_relative "tasks/mutant_shard"
    puts MutantShard.subjects_since(args[:ref] || "origin/main")
  end

  desc "Mutation-test shard INDEX of TOTAL over the subjects touched since REF"
  task :shard, [:ref, :index, :total] do |_task, args|
    index = Integer(args.fetch(:index))
    total = Integer(args.fetch(:total))
    require_relative "tasks/mutant_shard"
    subjects = MutantShard.subjects_since(args[:ref] || "origin/main")
    mine = MutantShard.shard(subjects, index, total)

    if mine.empty?
      puts "Shard #{index} of #{total}: no subjects"
    else
      puts "Shard #{index} of #{total}: #{mine.size} of #{subjects.size} subjects"
      sh "bundle exec mutant run #{mine.map { |subject| Shellwords.escape(subject) }.join(" ")}"
    end
  end
end

desc "Differential-fuzz the branch extractor against Ruby's Coverage (SEEDS, PER_SEED)"
task :fuzz, [:seeds, :per_seed] do |_task, args|
  # The suite's own-coverage dogfooding enforces 100% line coverage at exit,
  # which a single spec file can never reach.
  ENV["SIMPLECOV_NO_DOGFOOD"] = "1"
  ENV["SIMPLECOV_FUZZ"] = "1"
  ENV["SIMPLECOV_FUZZ_SEEDS"] = args[:seeds] if args[:seeds]
  ENV["SIMPLECOV_FUZZ_PER_SEED"] = args[:per_seed] if args[:per_seed]
  sh "bundle exec rspec spec/simple_cov/static_coverage_extractor_fuzz_spec.rb"
end

namespace :benchmark do
  desc "Iterations per second for formatting a Result"
  task :result do
    sh "bundle", "exec", "ruby", "benchmarks/result.rb"
  end

  desc "Iterations per second for simulating coverage of tracked-but-unloaded files"
  task :simulate_coverage do
    sh "bundle", "exec", "ruby", "benchmarks/simulate_coverage.rb"
  end

  desc "Per-phase report timings over a synthetic project of FILES files"
  task :report_scale, [:files] do |_task, args|
    command = ["bundle", "exec", "ruby", "benchmarks/report_scale.rb"]
    command << args[:files] if args[:files]
    sh(*command)
  end

  desc "Per-phase collate timings recorded under LABEL, optionally compared against BASELINE"
  task :collate, [:label, :baseline] do |_task, args|
    command = ["bundle", "exec", "ruby", "benchmarks/collate.rb"]
    command << args[:label] if args[:label]
    command += ["--baseline", args[:baseline]] if args[:baseline]
    sh(*command)
  end
end

namespace :frontend do
  desc "Install the frontend dependencies with bun"
  task :install do
    in_frontend("Frontend dependency installation") { sh "bun", "install", "--frozen-lockfile" }
  end

  desc "Lint the frontend TypeScript with oxlint"
  task lint: :install do
    in_frontend("Frontend linting") { sh "bun", "run", "lint" }
  end

  desc "Type-check the frontend TypeScript with tsc"
  task typecheck: :install do
    in_frontend("Frontend type checking") { sh "bun", "run", "typecheck" }
  end

  desc "Run the frontend TypeScript tests with bun (100% coverage enforced)"
  task test: :install do
    in_frontend("Frontend tests") { sh "bun", "test" }
  end

  desc "Mutation-test the frontend TypeScript with Stryker (slow)"
  task mutate: :install do
    in_frontend("Frontend mutation testing") { sh "bun", "run", "mutate" }
  end
end

desc "Validate the RBS type signatures in sig/"
task :rbs do
  require "rbs"
  sh "rbs", "-r", "forwardable", "-r", "monitor", "-r", "prism", "-r", "socket", "-r", "tempfile",
    "-I", "sig", "validate"
rescue LoadError
  warn "RBS is disabled"
end

desc "Type-check lib/ against sig/ with Steep (strict mode)"
task :steep do
  require "steep"
  sh "steep", "check"
rescue LoadError
  warn "Steep is disabled"
end

desc "Lint both sides, Ruby with Standard and RuboCop and the frontend with oxlint"
task lint: %i[standard rubocop frontend:lint]

desc "Type-check both sides, Ruby against sig/ and the frontend TypeScript"
task typecheck: %i[rbs steep frontend:typecheck]

task test: %i[spec frontend:test]
task default: %i[lint typecheck test]

def in_frontend(what, &)
  return warn("#{what} is disabled (bun is not installed)") unless
    system("bun", "--version", out: File::NULL, err: File::NULL)

  Dir.chdir(File.expand_path("html_frontend", __dir__), &)
end

def frontend_esbuild(frontend)
  executable = Gem.win_platform? ? "esbuild.cmd" : "esbuild"
  path = File.join(frontend, "node_modules", ".bin", executable)
  return path if File.file?(path)

  raise "Frontend esbuild not found at #{path}; run `bun install` in html_frontend"
end

def compile_frontend_js(frontend)
  require "tmpdir"
  Dir.mktmpdir do |tmp|
    args = ["src/app.ts", "--bundle", "--minify", "--target=es2015", "--outfile=#{tmp}/application.js"]
    Dir.chdir(frontend) { sh frontend_esbuild(frontend), *args }
    File.read(File.join(tmp, "application.js"))
  end
end

def compile_frontend_css(frontend)
  css = %w[
    assets/stylesheets/reset.css
    assets/stylesheets/plugins/highlight.css
    assets/stylesheets/screen.css
  ].map { |f| File.read(File.join(frontend, f)) }.join("\n")

  mangle_css_custom_properties(minify_css(css, esbuild: frontend_esbuild(frontend)))
end

def minify_css(css, esbuild:)
  output, error, status = Open3.capture3(esbuild, "--minify", "--loader=css", stdin_data: css)
  return output if status.success?

  raise "CSS compilation failed (exit #{status.exitstatus || "unknown"}): #{error.strip}"
end

# Custom properties that JavaScript reads or writes by name and must therefore
# survive mangling. Any `setProperty` / `getPropertyValue` call added to
# html_frontend/src must have its property listed here.
JS_VISIBLE_CSS_VARS = %w[--bar-sizer-width --green --red --yellow].freeze

# The stylesheets lean on descriptively named custom properties and every use
# repeats the full name, so the names alone cost ~4KB after minification.
# They are internal to the compiled template, so they are renamed to short
# aliases, most frequent first. The single gsub applies the whole mapping in
# one pass over full `--name` tokens, so `--text` cannot clobber
# `--text-secondary` and renames cannot chain.
#
# The lookbehind matches only genuine custom properties: a custom property's
# `--` always follows a separator, whereas a BEM class modifier's does not.
# It keeps the mangler off class names, where aliasing a `.cell--numerator`
# selector would desync it from the `class="cell--numerator"` the JS emits.
def mangle_css_custom_properties(css)
  token = /(?<![\w-])--[a-zA-Z][\w-]*/
  counts = css.scan(token).tally.except(*JS_VISIBLE_CSS_VARS)
  aliases = short_css_names.reject { |name| counts.key?(name) }
  mapping = counts.sort_by { |name, count| [-count, name] }.map(&:first).zip(aliases).to_h
  css.gsub(token) { |name| mapping.fetch(name, name) }
end

def short_css_names
  letters = ("a".."z").to_a
  letters.map { |a| "--#{a}" } + letters.product(letters).map { |a, b| "--#{a}#{b}" }
end

# The bundles land inside <script>/<style> elements, where the HTML parser
# treats these sequences as element terminators. The current bundles contain
# none of them; refuse to build one that does rather than emit a template
# that truncates at render time.
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

    html = File.read(File.join(frontend, "src/index.html"))
    {
      "<!-- SIMPLECOV_CSS -->" => "<style>#{css}</style>",
      "<!-- SIMPLECOV_APP_JS -->" => "<script>#{js}</script>"
    }.each do |marker, replacement|
      html.sub!(marker) { replacement } || raise("Marker #{marker.inspect} not found in src/index.html")
    end
    File.write(File.join(outdir, "index.html"), html)
  end

  desc "Compile the frontend and fail when the checked-in template is stale"
  task check: :compile do
    template = "lib/simplecov/formatter/html_formatter/public/index.html"
    Dir.chdir(__dir__) { sh "git", "diff", "--exit-code", "--", template }
  end
end

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

desc "Run the RSpec suite across parallel workers"
# Splitting by runtime matters here: the sandbox spec files are tiny on disk
# but each spends seconds driving fixture subprocesses, so the default
# file-size split parks them on a couple of workers. The RuntimeLogger in
# .rspec_parallel records per-file runtimes during every parallel run. The
# first run has no log yet and splits by size, and --allowed-missing 100 keeps
# a log that predates new or renamed spec files from failing the run.
task :spec do
  require "parallel_tests"
  rm_rf "tmp/dogfood-partials"
  grouping = File.size?("tmp/parallel_runtime_rspec.log") ? "--group-by runtime --allowed-missing 100 " : ""
  sh "bundle exec parallel_rspec --serialize-stdout #{grouping}spec"
rescue LoadError
  Rake::Task[:"spec:serial"].invoke
end

begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new
rescue LoadError
  task :rubocop do
    warn "Rubocop is disabled"
  end
end

desc "Regenerate man/simplecov.1 from the usage document"
task :man do
  require_relative "tasks/man_page"
  mkdir_p "man"
  File.write("man/simplecov.1", ManPage.build)
end

desc "Mutation-test the whole lib with mutant (slow)"
task :mutant do
  sh "bundle exec mutant run"
end

# The subjects mutant selects for a diff. Mutant matches each subject's line
# range against the diff, so a comment removed above a method marks every
# method below it as touched: a formatting pass over the tree selects most of
# the library. `mutant:shard` exists so that case fans out instead of running
# for hours in one job.
def mutant_subjects_since(ref)
  output, status = Open3.capture2("bundle", "exec", "mutant", "environment", "subject", "list", "--since", ref)
  raise "mutant could not list the subjects touched since #{ref}" unless status.success?

  # A subject name never contains a space, which is what tells it apart from
  # the "Subjects in environment: N" line mutant ends the listing with.
  output.lines.map(&:chomp).select { |line| line.start_with?("SimpleCov") && !line.include?(" ") }
end

# Round robin rather than contiguous slices. Mutant lists subjects sorted, so a
# namespace lands together and the expensive ones cluster: every
# `SimpleCov::CLI::Diff` subject shells out, and contiguous slicing would put
# them all in one shard, which is the shard that times out. Taking every
# TOTAL-th subject spreads a slow namespace across every runner instead.
def mutant_shard(subjects, index, total)
  subjects.select.with_index { |_subject, position| position % total == index }
end

namespace :mutant do
  desc "Mutation-test only the subjects touched since REF (default origin/main)"
  task :since, [:ref] do |_task, args|
    sh "bundle exec mutant run --since #{args[:ref] || 'origin/main'}"
  end

  desc "List the subjects touched since REF, one per line"
  task :subjects, [:ref] do |_task, args|
    puts mutant_subjects_since(args[:ref] || "origin/main")
  end

  desc "Mutation-test shard INDEX of TOTAL over the subjects touched since REF"
  task :shard, [:ref, :index, :total] do |_task, args|
    index = Integer(args.fetch(:index))
    total = Integer(args.fetch(:total))
    subjects = mutant_subjects_since(args[:ref] || "origin/main")
    mine = mutant_shard(subjects, index, total)

    if mine.empty?
      puts "Shard #{index} of #{total}: no subjects"
    else
      puts "Shard #{index} of #{total}: #{mine.size} of #{subjects.size} subjects"
      sh "bundle exec mutant run #{mine.map { |subject| Shellwords.escape(subject) }.join(' ')}"
    end
  end
end

namespace :frontend do
  desc "Run the frontend TypeScript tests with bun (100% coverage enforced)"
  task :test do
    if system("bun", "--version", out: File::NULL, err: File::NULL)
      Dir.chdir(File.expand_path("html_frontend", __dir__)) { sh "bun", "test" }
    else
      warn "Frontend tests are disabled (bun is not installed)"
    end
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
  require "rbs"
  sh "steep", "check"
rescue LoadError
  warn "Steep is disabled"
end

task test: %i[spec frontend:test]
task default: %i[rubocop rbs steep spec frontend:test]

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

  raise "CSS compilation failed (exit #{status.exitstatus || 'unknown'}): #{error.strip}"
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

# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../benchmarks/collate/file_structure"

# Inputs shared by the benchmarks in duel/. Every one is built from a fixed
# seed, so the baseline's workers and the candidate's see the same input,
# byte for byte, and every iteration sees the same input as the last. None
# is built with SimpleCov's own code, which differs between the versions.
#
# The synthetic projects come from the collate benchmark's generator
# (benchmarks/collate), which reproduces the file sizes, branch counts and
# hit counts of a large application's parallel CI run. A project is named by
# its number of files: 20 is a small gem, 200 a typical application, and
# 1,836 the collate benchmark's own project.
module DuelFixtures
  extend self

  SEED = 20_240_517

  # Where the in-memory projects' files claim to live. Nothing reads them
  # from disk, so the path is the same in every worker.
  ROOT = "/duel/project"
  ROOT_REGEX = %r{\A#{Regexp.escape(ROOT)}/}

  # Checked-in Ruby sources, for the work that parses real code.
  FIXTURES = File.expand_path("fixtures", __dir__)

  # Projects written to disk, for a Result, which drops a file it can't
  # find, and reads each one's source. Under tmp/, which git ignores. The
  # benchmarks always come from the candidate's tree, so the baseline's
  # workers read the same paths as the candidate's.
  GENERATED = File.expand_path("../tmp/duel_fixtures", __dir__)

  # A test's reach in a typical suite: the files whose lines it ran.
  FILES_A_TEST_TOUCHES = 10

  # Receivers for synthetic method coverage, one of them a singleton class,
  # whose key Coverage writes as `#<Class:...>`.
  class Widget; end
  class Ledger; end
  RECEIVERS = [Widget, Ledger, Widget.singleton_class].freeze

  # Each file's relative path, line counts, and branch table, keyed as a
  # resultset read back from JSON keys it.
  def structure(files)
    (@structures ||= {})[files] ||= CollateBenchmark::FileStructure.new(
      scale: CollateBenchmark::Shape::FILES / files.to_f, seed: SEED
    ).call
  end

  # The coverage of each of `count` shards of a parallel run over a project
  # of `files` files, as each shard's resultset holds it. The shards share
  # their files and branch keys, and differ only in a few hit counts.
  def shards(files, count, root: ROOT)
    entries = structure(files)
    rng = Random.new(SEED + count)
    Array.new(count) do
      entries.to_h do |entry|
        coverage = {"lines" => drift(entry.lines, rng), "branches" => entry.branches}
        [File.join(root, entry.relative_path), coverage]
      end
    end
  end

  # A copy of `lines` with as many hit counts grown as differ between two
  # shards of one run.
  def drift(lines, rng)
    lines.map do |hits|
      next hits if hits.nil? || rng.rand >= CollateBenchmark::Shape::SHARD_DRIFT_FRACTION

      hits + rng.rand(1..4)
    end
  end

  # One shard's `.resultset.json`, as a String.
  def resultset_json(files)
    coverage = shards(files, 1).first
    JSON.pretty_generate("RSpec" => {"coverage" => coverage, "timestamp" => 1_700_000_000})
  end

  # The directory of the project of `files` files on disk, and its coverage.
  # Written once, by whichever worker gets there first: the others wait on
  # the lock, and find it written.
  def project(files)
    root = File.join(GENERATED, "project-#{files}")
    FileUtils.mkdir_p(GENERATED)
    File.open(File.join(GENERATED, ".lock"), File::RDWR | File::CREAT) do |lock|
      lock.flock(File::LOCK_EX)
      write_project(root, structure(files)) unless File.exist?(File.join(root, ".complete"))
    end
    [root, shards(files, 1, root: root).first]
  end

  def write_project(root, entries)
    FileUtils.rm_rf(root)
    entries.each do |entry|
      path = File.join(root, entry.relative_path)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, source_body(entry.lines))
    end
    File.write(File.join(root, ".complete"), "")
  end

  # Source as long as the coverage says: a statement where Coverage counted
  # a line, and a comment where it didn't.
  def source_body(lines)
    lines.each_with_index.map do |hits, index|
      if hits.nil?
        "    # notes on why line #{index + 1} behaves the way it does\n"
      else
        "    value_#{index} = compute(record_#{index}, key: :option_#{index % 7})\n"
      end
    end.join
  end

  # A fresh Result over `coverage`, with every file's source read. Named, so
  # that SimpleCov doesn't guess at a test framework, and warn.
  def loaded_result(coverage)
    SimpleCov::Result.new(coverage, command_name: "RSpec").tap { |result| result.files.each(&:src) }
  end

  # Every file's section of the JSON report, as the formatter builds them.
  def file_sections(result, include_source:)
    result.files.map do |file|
      SimpleCov::Formatter::JSONFormatter::SourceFileFormatter.call(file, include_source: include_source)
    end
  end

  # The largest file of a project on disk, and its coverage.
  def largest_file(coverage)
    coverage.max_by { |_path, file_coverage| file_coverage["lines"].size }
  end

  # A checked-in Ruby source from duel/fixtures, as lines.
  def source_lines(name)
    File.readlines(File.join(FIXTURES, name))
  end

  def source_path(name)
    File.join(FIXTURES, name)
  end

  # What `Coverage.result` answers for the project of `files` files, before
  # SimpleCov adapts it: Symbol criteria, Array branch keys, and method keys
  # that start with the receiver itself. Built anew on every call, because
  # adapting it changes it in place.
  def raw_coverage(files)
    structure(files).to_h do |entry|
      [File.join(ROOT, entry.relative_path), raw_file_coverage(entry)]
    end
  end

  def raw_file_coverage(entry)
    branches = entry.branches.to_h do |condition, arms|
      [tuple(condition), arms.to_h { |arm, hits| [tuple(arm), hits] }]
    end
    {lines: entry.lines.dup, branches: branches, methods: raw_methods(entry.lines)}
  end

  # A method every tenth line, called when its first line ran.
  def raw_methods(lines)
    (0...lines.size).step(10).to_h do |index|
      receiver = RECEIVERS[(index / 10) % RECEIVERS.size]
      key = [receiver, :"method_#{index}", index + 1, 2, [index + 9, lines.size].min, 5]
      [key, lines[index] || 0]
    end
  end

  # A resultset's key, such as `[:if, 0, 3, 4, 3, 21]` or `[:"&.", ...]`,
  # back as the Array that Coverage keys with.
  def tuple(key)
    key.delete("[]").split(", ").map { |part| part.start_with?(":") ? part.delete(':"').to_sym : Integer(part) }
  end

  # Two of `Coverage.peek_result`'s snapshots of the project of `files`
  # files, taken before and after a test: the test grew a few lines in
  # FILES_A_TEST_TOUCHES of them. The project's files are among as many
  # files of gems, outside the root, as a peek covers every file loaded.
  def peeks(files)
    entries = structure(files)
    before = entries.to_h { |entry| [File.join(ROOT, entry.relative_path), {lines: entry.lines}] }
    entries.each_with_index do |entry, index|
      before["/duel/gems/gem-#{index}/lib/#{File.basename(entry.relative_path)}"] = {lines: entry.lines}
    end
    after = before.transform_values { |coverage| {lines: coverage.fetch(:lines).dup} }
    touched = after.keys.first(files).each_slice(files / FILES_A_TEST_TOUCHES).map(&:first)
    touched.each { |path| grow(after.fetch(path).fetch(:lines)) }
    [before, after]
  end

  # Every fifth line that counted, run once more.
  def grow(lines)
    lines.each_index { |index| lines[index] += 1 if lines[index] && (index % 5).zero? }
  end

  # The test map of a suite of `tests` tests over the project of `files`
  # files, as a resultset holds it: each test ran a stretch of lines in
  # FILES_A_TEST_TOUCHES files.
  def context_map_hash(files, tests)
    paths = structure(files).map { |entry| [File.join(ROOT, entry.relative_path), entry.lines.size] }
    rng = Random.new(SEED)
    tables = Hash.new { |hash, path| hash[path] = {} }
    tests.times do |test|
      paths.sample(FILES_A_TEST_TOUCHES, random: rng).each do |path, size|
        first = rng.rand(size)
        bitmap = ((1 << rng.rand(1..[size - first, 30].min)) - 1) << first
        tables[path][test.to_s] = bitmap.to_s(16)
      end
    end
    contexts = Array.new(tests) { |test| "spec/models/widget_#{test / 20}_spec.rb[1:#{test % 20 + 1}]" }
    {"version" => 1, "contexts" => contexts, "files" => tables.sort.to_h}
  end
end

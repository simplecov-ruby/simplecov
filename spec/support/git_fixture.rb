# frozen_string_literal: true

require "digest"
require "fileutils"
require "tmpdir"

# A git repository for an example to work in.
#
# Building one costs five git processes, and the specs that need a
# repository need the same handful of shapes over and over: the CLI
# subcommands that read a diff run against a fixture whose contents never
# vary. So each distinct shape is built once and copied per example. A
# copy is a third of the price of a build, and the example still gets a
# repository nothing else has touched.
#
# The copy is what keeps this safe. Reusing one repository and resetting
# it between examples would be faster still, and would reintroduce
# exactly the shared state these specs have been fixed to avoid.
#
# The template lives on disk under `tmp/`, keyed by a digest of its
# contents, rather than in memory. Mutant forks a process per mutation,
# and a template memoized in the parent is rebuilt by every fork that
# did not inherit it, which is the cost this exists to avoid. On disk,
# the first process to want a shape builds it and every process after
# that finds it.
module GitFixture
  extend self

  CACHE_ROOT = File.expand_path("../../tmp/git-fixtures", __dir__)

  # A repository at `files`, ready to diff against. The caller owns the
  # directory and removes it.
  def checkout(files)
    dir = Dir.mktmpdir("simplecov-git-fixture-")
    FileUtils.cp_r(File.join(template(files), "."), dir)
    dir
  end

  def template(files)
    path = File.join(CACHE_ROOT, digest(files))
    build(files, path) unless File.directory?(path)
    path
  end

  def digest(files)
    Digest::SHA256.hexdigest(files.sort.inspect)[0, 16]
  end

  # Built beside its destination and moved into place, so a second
  # process racing this one never copies a half-built repository: the
  # rename is atomic, and whichever process loses the race just discards
  # the template it built.
  def build(files, path)
    FileUtils.mkdir_p(CACHE_ROOT)
    staging = Dir.mktmpdir("simplecov-git-template-", CACHE_ROOT)
    write_all(files, staging)
    init(staging)
    File.rename(staging, path)
  rescue SystemCallError
    FileUtils.rm_rf(staging)
    raise unless File.directory?(path)
  end

  def write_all(files, dir)
    files.each do |name, content|
      full = File.join(dir, name)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
    end
  end

  # An empty template directory rather than git's own: the sample hooks
  # it would install are sixteen of the repository's thirty-seven files,
  # and every one of them would be copied again per example.
  def init(dir)
    init_repo(dir)
    commit!(dir, "init")
  end

  # An empty repository, in one git process rather than five. The
  # settings are appended to the config file the init just wrote, which
  # is the same file a run of `git config` per line would have edited.
  #
  # git 2.46+ forks a detached `git maintenance` after commits; its
  # transient .git/objects/maintenance.lock races an after-hook's
  # directory removal, so every fixture repository opts out of both that
  # and gc.
  def init_repo(dir, branch: "main")
    Dir.mktmpdir("simplecov-git-empty-template-") do |empty|
      git!("-c", "init.defaultBranch=#{branch}", "init", "-q", "--template=#{empty}", dir)
    end
    File.write(File.join(dir, ".git", "config"), CONFIG, mode: "a")
  end

  CONFIG = <<~CONFIG
    [user]
    \temail = spec@example.com
    \tname = spec
    [maintenance]
    \tauto = false
    [gc]
    \tauto = 0
  CONFIG

  def commit!(dir, message)
    git!("-C", dir, "add", "-A")
    git!("-C", dir, "-c", "user.email=spec@example.com", "-c", "user.name=spec",
         "commit", "-qm", message)
  end

  def git!(*argv)
    system("git", *argv, exception: true)
  end
end

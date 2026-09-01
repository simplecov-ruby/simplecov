# frozen_string_literal: true

require "digest"
require "fileutils"
require "tmpdir"

module GitFixture
  extend self

  CACHE_ROOT = File.expand_path("../../tmp/git-fixtures", __dir__)

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

  def init(dir)
    init_repo(dir)
    commit!(dir, "init")
  end

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

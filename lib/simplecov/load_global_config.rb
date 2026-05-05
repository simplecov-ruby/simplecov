# frozen_string_literal: true

require "etc"
# Don't use `Dir.home`: it raises `ArgumentError` on JRuby when `HOME` is
# unset, defeating the fall-through to `Etc.getpwuid.dir` and `ENV["USER"]`.
home_dir =
  (ENV.fetch("HOME", nil) && File.expand_path("~")) ||
  Etc.getpwuid.dir ||
  (ENV.fetch("USER", nil) && File.expand_path("~#{ENV.fetch('USER', nil)}"))
if home_dir
  global_config_path = File.join(home_dir, ".simplecov")
  load global_config_path if File.exist?(global_config_path)
end

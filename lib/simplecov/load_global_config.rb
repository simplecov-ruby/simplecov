# frozen_string_literal: true

require "etc"
home_dir = Dir.home || File.expand_path("~") || Etc.getpwuid.dir || (ENV.fetch("USER", nil) && File.expand_path("~#{ENV.fetch('USER', nil)}"))
if home_dir
  global_config_path = File.join(home_dir, ".simplecov")
  load global_config_path if File.exist?(global_config_path)
end

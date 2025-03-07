ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

# Previously some gems masked a bug in Rails v6 and v7 where `logger` was not required,
#   plugging the hole by requiring it themselves.
# Because this app is pinned to Rails v6.1, we must require logger manually.
# In order to not be reliant on other libraries to fix the bug in Rails for us, we do it too.
# See: https://stackoverflow.com/questions/79360526/uninitialized-constant-activesupportloggerthreadsafelevellogger-nameerror
require "logger"

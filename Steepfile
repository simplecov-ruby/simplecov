# frozen_string_literal: true

target :lib do
  signature "sig"

  check "lib"

  library "coverage"
  library "fileutils"
  library "forwardable"
  library "json"
  library "open3"
  library "optparse"
  library "socket"
  library "time"
  library "prism"
  library "ripper"

  configure_code_diagnostics(Steep::Diagnostic::Ruby.strict)
end

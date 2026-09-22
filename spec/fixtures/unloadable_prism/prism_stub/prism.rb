# frozen_string_literal: true

# Stands in for a Prism whose native library cannot load, as on JRuby on
# Windows: the FFI backend raises after `module Prism` is already open.
module Prism
end

raise LoadError, "Could not open library 'libprism'"

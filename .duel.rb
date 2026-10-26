# frozen_string_literal: true

# Duel's configuration: https://github.com/sferik/duel-ruby/blob/main/docs/configuration.md
#
# Duel follows conventions, so set only what differs: benchmarks are in
# duel/**/*_duel.rb, each version's lib/ is first on the load path, a
# change is compared when it touches lib/ or ext/, and releases are
# tagged v*.
Duel.configure do |c|
  # SimpleCov runs inside a test suite's process for the whole run, and
  # keeps caches for that long: the branch and method keys it has parsed
  # and interned, and which files are under the project's root. Each is
  # bounded by the project's size, so a benchmark that leaves more alive
  # with every call has a leak.
  c.use :retained

  # Compare a change to the benchmarks, this file or the Perf workflow
  # too, not only to lib/ and ext/.
  c.watch += %w[duel .duel.rb .github/workflows/perf.yml]
end

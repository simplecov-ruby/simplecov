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

  # Compare a change to only the Perf workflow too.
  c.watch += %w[.github/workflows/perf.yml]

  # A regression fails a pull request (or a merge queue), but in a push
  # to the main branch, the schedule, or a run by hand, it only warns,
  # and the workflow comments on the pushed commit with the report,
  # which notifies its author.
  c.fail_on = :pull_requests

  # A pull request with this label passes with a regression, which the
  # report says the label accepted (after adding the label, run the
  # workflow again).
  c.accept_label = "duel: accept"

  # A push is compared with the last commit Duel passed, which a branch
  # marks (duel/passed/main for main), not the commit before it, so
  # slowdowns too small for any one push to fail add up until they fail
  # one. To accept a regression after it's pushed, move that branch:
  # git push origin main:duel/passed/main.
  c.push_base = :last_passed
end

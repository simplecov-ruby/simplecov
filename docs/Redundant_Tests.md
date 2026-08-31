# Finding redundant tests

Using `track_tests` and `simplecov tests --redundant` to find and safely remove tests that add nothing to your
suite's coverage.

*Part of the [SimpleCov](../README.md) documentation.*

Suites accumulate tests. Some of them cover code a dozen other tests also cover, assert nothing those tests don't
already assert, and cost runtime on every push. SimpleCov can identify the candidates, and this guide is the
workflow for turning that list into deletions without quietly weakening the suite.

## Record which test covers each line

Enable [`track_tests`](Configuration.md#tracking-which-test-covers-each-line) and the JSON formatter, then run your
suite once:

```ruby
SimpleCov.start do
  enable_coverage :branch
  track_tests
  formatter SimpleCov::Formatter::JSONFormatter
end
```

The resulting `coverage/coverage.json` carries a per-test recording: which lines each test executed. Everything
below reads that file, so a single instrumented run is enough, and you can keep the flag off day to day (recording
costs time on every example, see the configuration docs for the cost model and the `granularity: :file` lever).

Check the recording took: `simplecov tests` should list your test ids. If it's empty under a parallel runner, run
the recording pass serially. A merge only keeps the recording when every merged result carries one, so one worker
without it (or one that crashed mid-run) silently drops the map for all of them.

## Ask for the redundant tests

```sh
$ simplecov tests --redundant
spec/user_spec.rb:87
spec/user_spec.rb:203
spec/orders/refund_spec.rb:41
```

A test is listed when no line anywhere in your code is covered by that test alone. Every line it executes has at
least one other witness, so deleting it cannot change line coverage. `simplecov tests --redundant lib/foo.rb`
narrows the sweep to the tests touching one file, which is a good way to work through a large list area by area.

## Read the list as candidates, not a verdict

Expect the list to be long, and expect most of it to be false positives. Line coverage cannot see most of the ways
a test earns its keep:

* **Distinct assertions on shared lines.** A table of examples feeding different values through the same code path
  all execute identical lines, and each one can catch a regression none of its siblings would. This is the most
  common false positive, and in a well-factored unit suite it is most of the suite.
* **Branch arms and methods.** Two tests can cover identical lines while taking different branches. If you enforce
  branch or method coverage, the re-run below catches this. If you don't, a line-identical pair can still differ in
  what it proves.
* **Coverage that happens somewhere the recording cannot see.** A test that shells out to a subprocess, drives a
  fixture project, or asserts on something other than your instrumented code (generated files, output contracts,
  a gemspec) records few or no lines of its own. Those tests look maximally redundant and are usually load-bearing.
  Set them aside before triaging anything else.
* **Subsuming pairs.** Two tests covering exactly the same lines are both listed, because each one's lines are fully
  covered by the other. Deleting both loses the lines. Remove one, regenerate the report, and look again.

The genuinely dead test, the one that duplicates a sibling's coverage and its assertions, lives inside this list.
The rest of the workflow is separating it from the tests that merely look dead.

## Delete behind gates

Work in small batches and make each gate cheap to re-run:

1. **Triage by eye.** For each candidate, ask what would break if it were gone. `simplecov tests path:line` names
   the other tests covering any line you're unsure about, which is often enough to spot the sibling that makes a
   candidate a true duplicate rather than a distinct assertion.
2. **Re-run with thresholds.** Delete a batch, re-run the suite, and compare line, branch, and method coverage
   against the pre-deletion report (`minimum_coverage` with all three criteria, or `simplecov diff`). Line coverage
   is guaranteed to hold by construction. Branch and method coverage are not, and a drop names exactly which
   candidate was covering an arm its line-twin never took. Restore it.
3. **Let mutation testing arbitrate, if you have it.** Coverage cannot tell a value-asserting test from a redundant
   one, but a mutation tool ([mutant](https://github.com/mbj/mutant), for example) can: delete the batch, run
   mutations over the affected code, and every newly surviving mutation names a test that was killing it. Restore
   those. This is the only gate that catches the distinct-assertions case, so without mutation testing, be far more
   conservative in step 1.
4. **Regenerate and repeat.** Deletions change what is uniquely covered, so regenerate the recording between rounds
   rather than working through a stale list.

## Calibration: what to expect

Running this workflow on SimpleCov's own suite flagged 97% of the recorded tests as line-redundant. After the gates
above (branch arms restored a few hundred candidates, mutation testing rejected nearly all the rest), fifteen tests
out of more than four thousand were actually removable. That ratio is what a suite already shaped by mutation
testing looks like, and it is the calibration to carry into your own sweep: the flagged set is where any dead
weight must live, a test the sweep does not flag is certainly pulling its weight, but the list itself is a place to
start asking, not a place to start deleting.

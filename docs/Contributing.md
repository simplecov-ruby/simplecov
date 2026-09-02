## Reporting Issues

You can report issues at https://github.com/simplecov-ruby/simplecov/issues

Before you go ahead please search existing issues for your problem, chances are someone else already reported it.

To make sure that we can help you quickly please include and check the following information:

 * Include how you run your tests and which testing framework or frameworks you are running.
    - please ensure you are requiring and starting SimpleCov before requiring any application code.
    - If running via rake, please ensure you are requiring SimpleCov at the top of your Rakefile
      For example, if running via RSpec, this would be at the top of your spec_helper.
    - Have you tried using a [`.simplecov` file](https://github.com/simplecov-ruby/simplecov#using-simplecov-for-centralized-config)?
 * Include the SimpleCov version you are running in your report.
 * If you are not running the latest version (please check), and you cannot update it,
   please specify in your report why you can't update to the latest version.
 * Include your `ruby -e "puts RUBY_DESCRIPTION"`.
 * Please also specify the gem versions of Rails (if applicable).
 * Include any other coverage gems you may be using and their versions.

Include as much sample code as you can to help us reproduce the issue. (Inline, repo link, or gist, are fine. A failing test would help the most.)

This is extremely important for narrowing down the cause of your problem.

Thanks!

## Making Contributions

To fetch & test the library for development, do:

    $ git clone https://github.com/simplecov-ruby/simplecov.git
    $ cd simplecov
    $ bundle
    $ bundle exec rake

The HTML report frontend is written in TypeScript and tested with [Bun](https://bun.sh).
Install Bun to run those tests (the rake task skips them with a warning otherwise):

    $ cd html_frontend
    $ bun install
    $ bun test

Style is whatever `rake lint` says, which is Standard plus a few RSpec rules.
`.rubocop.yml` deliberately holds almost nothing: a cop Standard disables stays
disabled no matter what you configure for it, so conventions that have to hold
are written down here instead. One that is easy to trip over: a command whose
name is a verb may still return a boolean. `stop`, `store`, `store_result`,
`remove_filter` and `warn_decline` report whether they acted, and the action is
the point while the boolean is the receipt, so neither a `?` nor a bare command
would read better.

If you want to contribute, please:

  * Fork the project.
  * Make your feature addition or bug fix.
  * Add tests for it. This is important so I don't break it in a future version unintentionally.
  * **Bonus Points** go out to anyone who also updates `CHANGELOG.md` :)
  * Send me a pull request on GitHub.

## Running Individual Tests

The Ruby suite uses RSpec (including the end-to-end sandbox specs in
`spec/sandbox`, which drive the fixture projects in `test_projects`), and the
frontend suite uses `bun test`. Individual tests can be run like this:

```bash
bundle exec rspec path/to/test_spec.rb
cd html_frontend && bun test test/format.test.ts
```

Note: single-file rspec runs fail the 100% self-coverage check by design.
Set `SIMPLECOV_NO_DOGFOOD=1` to skip it when running a subset.

## Mutation Testing

The suite is also held to account by [mutant](https://github.com/mbj/mutant),
configured in `.mutant.yml` with the full operator set. Mutant rewrites one
method at a time and re-runs the tests that cover it, so a mutation nobody
notices is a behavior nobody pinned. Run it over the code you touched:

```bash
bundle exec mutant run 'SimpleCov::CLI::Patch*'   # one namespace, seconds
bundle exec rake mutant:since                      # subjects touched since origin/main
bundle exec rake mutant                            # the whole lib, slow
```

Pull requests run `mutant:since` against their base branch in CI, so a change
is answerable for the mutations it introduces without waiting on the whole
library. A pull request that touches no library code selects no subjects and
passes.

Where the library's own shape makes mutation testing slower or harder than it
needs to be, and what a major version could do about it, is written down in
[docs/Roadmap.md](Roadmap.md).

The HTML frontend has the same check in [Stryker](https://stryker-mutator.io),
configured in `html_frontend/stryker.config.mjs`. Its tests run under
`bun test`, which Stryker has no runner plugin for, so it runs the whole suite
per mutant through the command runner and writes an HTML report to
`html_frontend/reports/mutation/index.html`:

```bash
bundle exec rake frontend:mutate                   # every src module, about ten minutes
cd html_frontend && bun run mutate --mutate src/sort.ts   # one module, seconds
```

Three suite conventions keep mutant fast and honest, and touching them breaks
it quietly, so know they exist:

* Library modules use `extend self`, never `module_function`.
  `module_function` copies each method to a second singleton definition and
  callers dispatch to the copy, so mutant's re-inserted instance methods would
  be invisible and every mutation would survive. Nothing checks this for you,
  because Standard disables the cop that would.
* Spec describes that don't name a constant carry a `mutant_expression`
  metadata tag naming the namespace they exercise (see `spec/simple_cov/cli_spec.rb`), so
  mutant selects only those examples for the namespace's subjects. An
  untagged group is selected for every subject in the file's top constant,
  which is slow. Specs that only observe subprocesses can't kill an in-memory
  mutation at all and are tagged `mutant: false`.
* A provably equivalent mutation (the tests cannot ever tell it apart) is
  disabled at its definition site with a `# mutant:disable` comment naming the
  equivalence, and the method's behavior is pinned by unit examples instead.

### Selecting the right tests

Mutant offers a subject the tests from the **most specific expression that
matches any**, and stops there. That one rule explains most surprises:

* A `describe ".method"` block gives its examples that method's exact
  expression, so a subject with such a block is offered only that block's
  examples. Examples elsewhere in the same file are never considered for it,
  however directly they exercise it.
* Tagging a describe at a level *deeper* than the pool that already covers the
  code replaces that pool rather than joining it. Tagging at the *same* level
  merges the two.
* RSpec joins a class describe and a `#method` / `.method` description without
  a space, so `describe "#thing"` inside `RSpec.describe Klass` reads as
  `Klass#thing` and gives that subject an exact pool. Adding such a block to
  hold new examples starves the subject of every example outside it, which
  looks exactly like a wave of new survivors.
* Worse, the pool can end up empty rather than merely narrow. Mutant reads the
  first whitespace-delimited token of an example's full description, so
  `describe "#overlaps_with?(range)"` glues into
  `Klass#overlaps_with?(range)`, which is not an expression anything can
  parse, and every example in the group leaves mutant's view. Seven examples
  sat behind one of those and twenty-nine mutations survived in front of it.
  Name such a group so the first token is either a bare expression or not one
  at all: `describe "#overlaps_with?"`, or prose with no leading `#`.
* So: tag a new describe with the expression the existing pool already uses,
  and add an exact-method expression only where such a block already exists.
  Creating an exact pool where none existed starves the subject.

### What cannot be killed

Some mutations are exact synonyms, and no test can tell them apart. Recognise
them rather than chasing them:

* `==` against `eql?` (and often `equal?`) where both operands are Strings,
  Symbols, or Integers.
* `defined?(@ivar)` against `instance_variable_defined?(:@ivar)`.
* `::Const` against `Const` where nothing of that name is nested.
* `map` against `flat_map` where the result is `join`ed, since `join` flattens.
* `is_a?` against `instance_of?` for a class with no subclass in play.
* A redundant guard whose absence changes nothing, which is worth deleting
  rather than disabling: mutant found dead code.

A mutation whose damage lands outside an example is caught by the
`process_abort` coverage criterion in `.mutant.yml`: a failure in an `after`
hook, or on the way out of the process, takes the run down with a failing
status and counts. Enable that criterion when reading survivors, or a
mutation the suite plainly kills by hand will read as surviving.

What that criterion cannot catch is a mutation that ends the process
*successfully*. Dropping `on_help` from a parser leaves optparse's officious
`--help`, which prints a summary and calls `exit` from inside the parser: the
process ends cleanly, before any result is recorded, and mutant reads the
zero status as a passing run. That is why every parser is built through
`CommandHelpers#build_parser`, which carries that one line, disabled, in a
single place.

Read the mutation before deciding it is equivalent. `unless X` becomes
`unless true`, which makes a guard *never* fire rather than always fire, so
the example that kills it is one where the guard's own case is the one that
matters. And a survivor that will not die under an example that plainly
covers it is worth running by hand: an equivalent-looking mutation of
`formatters=` turned out to be reporting a real regression, where rewriting
an assignment as a modifier had stopped an empty list from clearing the
formatter.

An equivalent mutation is often the tests asserting through something lossy
rather than the code being redundant. Reading a record back through JSON
stringifies its symbol keys; comparing an object with itself makes `equal?`
indistinguishable from `==`; recording the same run twice makes the newest
entry indistinguishable from the oldest. Fix the example rather than the
code where that is what is going on.

### Code that only runs on another Ruby

Version-gated code is invisible here, because the constant that gates it is
false on the Ruby you measure with. Two ways out, in order of preference:
call the gated logic directly where it is a pure function (the value-position
pass is exercised this way), or stub the constant and pin the conventions the
gated paths produce as a regression baseline (the legacy branch locations are
pinned this way). Say which one it is in the spec, so a reader knows whether
the expectations are ground truth or a frozen baseline.

# Roadmap

Where SimpleCov is heading: the target design for the configuration DSL, and the API changes that would make the
library faster and easier to hold to account under mutation testing. Completed work has been removed from this
page. What remains is open, and most of it waits on a major version.

*Part of the [SimpleCov](../README.md) documentation.*

## Configuration roadmap

The configuration surface has grown a keyword at a time for fifteen years, and it shows. The same threshold can be
spelled two ways (`minimum_coverage 90` and `coverage(:line) { minimum 90 }`), scope used to be encoded three ways
(in the bare verb, in a `_per_file` suffix, and in an `only:` keyword), old flat names say `_by_file` where newer
names say `_per_file`, and `:eval` rides the criteria switch despite not being a criterion. This section records the
target design and the deliberate, compatibility-preserving steps to it, so each future change lands as part of one
plan rather than as another accretion.

Phases 1 and 1.5 (the `per:` scope axis, criterion-scoped `ignore`, `formats`, and `deprecations :raise`) have
shipped, so the numbering below starts at 2.

### Principles

1. **One spelling per concept.** Every configurable thing has exactly one current spelling. Old spellings keep
   working through warn-and-delegate deprecations until a major version, but the docs teach only the current one.
2. **Axes are spelled once, not baked into names.** A threshold is a point in the space
   (criterion x metric x bound x scope). The criterion is fixed by the `coverage` block, the bound and metric by the
   verb (`minimum`, `maximum`, `maximum_missed`, `maximum_drop`), and the scope by a uniform `per:` argument.
   New cells of that matrix must come from composing the axes, never from minting a new method name.
3. **Three families, telegraphed by name.** Configuration answers three questions: what the runtime *measures*
   (criteria, eval, oneshot, subprocesses, per-test attribution), what the report *covers* (files, groups, views,
   formatters, paths), and what the exit check *enforces* (thresholds, caps, the baseline). A keyword's name should
   make its family obvious.
4. **Migrations are mechanical, and enforceable.** Every deprecation warning prints the exact replacement, built
   from the caller's own arguments, so migrating is copy-paste, and `deprecations :raise` turns the warnings into
   errors so a migrated project can guard against old spellings in CI. Nothing is removed before SimpleCov 2.0, and
   a configuration written against 1.x keeps working, warnings aside, until then.

### The target threshold grammar

```ruby
SimpleCov.start do
  coverage :line do
    minimum 90                          # suite-wide
    minimum 80,  per: :file             # every file
    minimum 100, per: "app/x.rb"        # one path (String or Regexp)
    minimum 95,  per: group("Models")   # a named group
    maximum_missed 12                   # suite-wide burn-down cap
    maximum_missed 5, per: :file
    maximum_drop 5
  end

  coverage :branch, minimum: 80, maximum_missed: 3
end
```

The block fixes the criterion so every value is a plain number, and `per:` carries the scope. Anything expressible
for one criterion is expressible for all of them, and anything expressible for one bound composes with every scope
the enforcement supports.

### Phase 2: fill the matrix

The `per:` axis makes the missing cells visible. In rough priority order:

- `maximum_missed N, per: group(...)`: a per-group miss cap. Needs a store, a check, an errors-section entry, and a
  schema addition, all mirroring the per-file cap.
- `maximum_drop N, per: ...`: per-file and per-group drop limits, using the same `.last_run.json` mechanism as the
  suite-wide drop.
- `refuse_new_misses`: the count analog of `refuse_coverage_drop`. "No more misses than the last run" is the
  ratchet sentiment without a checked-in baseline, and the algebra hands it to us: it is `maximum_drop 0` with the
  missed metric.

Each cell should ship only when its enforcement ships. A scope the checks cannot enforce is refused at configuration
time, the way `maximum_missed per: group(...)` is today.

### Phase 3: measurement family cleanup

- `:eval` stops pretending to be a criterion. It becomes a standalone toggle (working name: `eval_coverage true`),
  since it widens what the runtime instruments for *every* criterion rather than adding a fourth one.
  `enable_coverage :eval` and `coverage :eval` warn and delegate. The special cases in the criteria code
  (`raise_if_criterion_disabled`, the enabled-set exclusion) fall away with it.
- `track_tests` is already correctly named and placed. Once `track_files` (deprecated in favor of `cover`) is
  removed at 2.0, `track_` unambiguously means test attribution.
- `merge_subprocesses` / `enable_for_subprocesses`: converge on one name for the subprocess switch.
- One spelling for "primary". `primary_coverage :branch`, `coverage :branch, primary: true`, and the block verb
  `primary` all exist. The `coverage` forms are canonical (the criterion is right there); `primary_coverage` becomes
  a documented legacy alias, deprecated at 2.0.

### Phase 4: baseline unification

The baseline is configured in two places today: `baseline_file` names the path, and adding
`SimpleCov::Formatter::BaselineFormatter` to the formatter chain turns on auto-ratcheting. From scratch it is one
construct:

```ruby
baseline file: "config/coverage_floors.yml", auto_ratchet: true
```

`baseline_file` warns and delegates to `baseline file:`, and `auto_ratchet: true` installs the formatter internally,
demoting `BaselineFormatter` from user-facing switch to implementation detail (it stays public for formatter chains
that want explicit control).

### Phase 5: one grammar

Three grammar unifications, none urgent alone, all worth folding into releases that touch the same code:

- **Booleans.** `use_merging`, `merge_subprocesses`, `print_errors`, and `source_in_json` mix verb-phrase and
  noun-phrase styles. Converge on the noun-value style the rest of the DSL uses, with the old names as
  warn-and-delegate aliases. Every such setting already has an explicit `setting = value` writer, so the
  convergence is a naming decision, not a mechanism.
- **Matchers.** `cover "lib/**/*.rb"` takes a glob while `skip "lib/legacy"` takes a path-segment substring: two
  universe verbs, two String grammars, and the difference is invisible at the call site. Changing `skip`'s String
  semantics would silently alter which files existing configurations exclude, so the unification itself is a 2.0
  change. An explicit `skip glob("lib/**/*_generated.rb")` wrapper (mirroring `per: group(...)`) can bridge earlier
  for projects that want glob exclusion before then.
- **Exclusion comments.** The legacy `# :nocov:` toggles and the newer `# simplecov:disable` / `# simplecov:enable`
  directives do overlapping jobs with different syntax. The `nocov_token` configuration hook is already deprecated;
  what remains is retiring recognition of the `# :nocov:` comments themselves in favor of the criterion-aware
  directives, which is a 2.0 change because those comments live in thousands of shipped codebases.

A footnote rather than a phase: the merge family (`merging`, `merge_timeout`, `merge_subprocesses`,
`parallel_tests`, `command_name`, and the `SIMPLECOV_MERGE_TIMEOUT` variable) is one concern spread across six flat
names, and a `merge do ... end` sub-block would group it the way `coverage` groups thresholds. It adds structure
without removing anything, so it should only happen if the family grows again.

### Production coverage: placed, and split on purpose

`production_coverage PATH` names the store a `SimpleCov::Production` sink accumulated (see
[Production.md](Production.md)) and belongs to the report family: it changes what the report carries, not what the
runtime measures or the exit check enforces. The `*_coverage` name does not make it a criterion, any more than the
Phase 3 target name `eval_coverage` is one. What matters, per the `:eval` lesson, is that it never rides the
criteria switch.

Production configuration spans two surfaces on purpose, and the split must survive future unifications.
`SimpleCov::Production.start(root:, sink:, flush_interval:, ...)` configures the measuring process and stays outside
the DSL, because `.simplecov` is loaded by every test run and by the CLI's dotfile reader, and loading a config file
must never be able to boot a production measurement tap. Only the report-side pointer lives in the DSL, and the CLI
defaults `dead-code --production` from it the way `ratchet` defaults `--baseline` from `baseline_file`, so the DSL
is the single source of truth for where the store lives.

Growth follows the patterns already on this page. A second report-side knob (a staleness policy, multiple stores for
multiple environments) converges on the Phase 4 keyword-construct template
(`production_coverage file: ..., stale_after: ...`), never a second `production_*` flat name. And if the cross ever
feeds enforcement ("no untested lines running in production"), that cell belongs in the `coverage` block grammar as
a bound verb under principle 2, shipped only when its enforcement ships, per the Phase 2 rule.

### Phase 6 (SimpleCov 2.0): one surface

- Remove everything deprecated in Phases 1 through 5, plus the pre-existing deprecations
  (`track_files`, `add_filter`, `add_group`, `minimum_coverage_by_file`, `minimum_coverage_by_group`,
  `enable_coverage_for_eval`).
- Retire the flat threshold family (`minimum_coverage`, `maximum_coverage`, `maximum_coverage_drop`,
  `expected_coverage`, `maximum_missed`) in favor of the `coverage` block as the only threshold home. These are the
  most-used APIs in the gem, so they are the last to go and the deprecation runs for a full major cycle:
  soft-deprecate (docs only) during 1.x, warn at 2.0, remove no earlier than 3.0.
- Group the surface into the three families (`measure` / report verbs / `enforce`), whether as literal blocks or as
  documentation structure, so the config file reads in the order the data flows: what is measured, what is reported,
  what is enforced.

### What stays

The criterion-fixing `coverage` block, `cover` / `skip` / `group` as the universe verbs, `cover_views` (named into
the `cover` family on purpose), and the principle that the `.simplecov` file plus profiles remain the two
composition mechanisms. The getter-setter duality (`minimum_coverage` with no arguments reads, with arguments
writes) stays through 1.x, though the mutation-testing section below records its cost and the open question of
retiring it at a major version.

## Mutation testing roadmap

The suite is measured by [mutant](https://github.com/mbj/mutant) at the full operator set, and getting there taught
us where the library's shape fights the tool. Everything that could be done without breaking the API has been done:
the run's state lives on its own `SimpleCov::CurrentRun` object behind generated delegators, the exit path answers
its status instead of performing it, the threshold checks answer their reports as values, every dual-purpose
setting has an explicit writer, and every spec block names the subjects it covers. What remains is the part that
changes what callers may say.

### What the shape still costs

Mutation analysis re-runs, per mutation, the tests that cover the mutated subject, so a run's length is decided by
how many tests each subject drags in. Everything the library does still passes through one module: `SimpleCov`
carries the run's lifecycle and `SimpleCov::Configuration`, mixed into the same singleton, carries the settings.
Scoping every spec block cut the singleton's selected tests from 3,780 to a few hundred, but a subject on the
singleton remains a candidate for every example that touches the library at all, where a subject on an extracted
object selects only the examples about it.

### Split the singleton into objects with their own lives

**What remains, and why it breaks.** The lifecycle itself (start, finish, and the configuration a run reads) still
passes through the singleton, and the `CurrentRun` object that holds the run's state is internal. Moving the
lifecycle onto the run object, passing configuration to it rather than reading it from a global, and exposing the
object as API (with `SimpleCov.start` staying as the delegating front door) changes what the at_exit machinery and
every integrating formatter may hold a reference to, so it costs a major version.

**What it buys.** A spec names the object it exercises, so its subjects select the examples about them and nothing
else, and the largest namespaces measure in seconds rather than minutes.

### Retire the dual spelling of the settings

**What remains, and why it breaks.** Each setting's write behaviour now lives once, in its writer, but the
dual-purpose spelling (`SimpleCov.color(:never)` writes; `SimpleCov.color` reads) still exists, sentinel and all,
and every such method still carries two behaviours to pin. Retiring the dual spelling in favour of the writers,
with the DSL block keeping the bare-word spelling by evaluating against a builder, changes what configuration
files may say. The configuration roadmap above currently keeps the duality; this entry records the cost of keeping
it, and the two should be decided together at 2.0.

**What it buys.** Half as many behaviours per subject, no sentinel to compare, and defaults that are values to
assert rather than branches to reach.

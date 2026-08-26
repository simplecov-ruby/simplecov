# Configuration roadmap

Where the configuration DSL is heading, and the path from here to there.

*Part of the [SimpleCov](../README.md) documentation.*

## Configuration roadmap

The configuration surface has grown a keyword at a time for fifteen years, and it shows. The same threshold can be
spelled two ways (`minimum_coverage 90` and `coverage(:line) { minimum 90 }`), scope used to be encoded three ways
(in the bare verb, in a `_per_file` suffix, and in an `only:` keyword), old flat names say `_by_file` where newer
names say `_per_file`, and `:eval` rides the criteria switch despite not being a criterion. This document records the
target design and the deliberate, compatibility-preserving steps to it, so each future change lands as part of one
plan rather than as another accretion.

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

### Phase 1: the `per:` axis (done)

`minimum` and `maximum_missed` take `per:` with `:file`, String, Regexp, and `group("Name")` targets. The suffixed
verbs (`minimum_per_file`, `minimum_per_group`, `maximum_missed_per_file`, and the flat
`SimpleCov.maximum_missed_per_file` setter) warn and delegate, and the `minimum_coverage_by_file` /
`minimum_coverage_by_group` deprecation messages now suggest the `per:` grammar instead of the grammar that replaced
them the first time. `maximum_missed` refuses `per: group(...)` loudly, because the enforcement behind it does not
exist yet (see Phase 2), and refusing beats silently storing a cap nothing checks.

### Phase 1.5: uniformity groundwork (done)

Three smaller steps shipped on the same principles:

- `coverage(:branch) { ignore :implicit_else, :eval_generated }` and `coverage :method, ignore: :eval_generated`
  replace `ignore_branches` / `ignore_methods`, which had the criterion baked into their names the way the suffixed
  threshold verbs did. The flat setters warn and delegate; their one distinct behavior (recording the filter without
  enabling the criterion) rides out the deprecation period.
- `formats :html, :json` selects bundled formatters by name, ending the `SimpleCov::Formatter::HTMLFormatter`
  constant ritual for common combinations. Classes and instances mix beside the names for everything else.
- `deprecations :raise` makes every deprecated API a `ConfigurationError`, the enforcement lever behind principle 4.

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
  warn-and-delegate aliases.
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

The criterion-fixing `coverage` block, the getter-setter duality (`minimum_coverage` with no arguments reads, with
arguments writes), `cover` / `skip` / `group` as the universe verbs, `cover_views` (named into the `cover` family on
purpose), and the principle that the `.simplecov` file plus profiles remain the two composition mechanisms.

# Mutation testing roadmap

The API changes that would make this library faster and easier to hold to account. Each item's non-breaking core is
implemented; what remains of each is the part that changes what callers may say, and costs a major version.

*Part of the [SimpleCov](../README.md) documentation.*

## Mutation testing roadmap

The suite is measured by [mutant](https://github.com/mbj/mutant) at the full operator set, and getting there taught
us where the library's shape fights the tool. None of what follows is required to keep mutation coverage at 100%: it
is all already there. Every item below has been carried as far as it can go without breaking the API, and each notes
the remainder that cannot be.

The measurements quoted are from the 2026-08-28 sweep on a ten-core machine, where the whole library measures
51,777 mutations across 1,262 subjects at 100%. A full run takes between two and five hours depending on what else
the machine is doing.

### What the shape costs today

Mutation analysis re-runs, per mutation, the tests that cover the mutated subject. Two things therefore decide how
long a run takes: how many subjects a change touches, and **how many tests each subject drags in**. The second is
where the library's structure shows.

| Namespace | Tests per subject | Mutations/s |
| --- | --- | --- |
| `SimpleCov::ExitCodes` | 2.7 | 116 |
| `SimpleCov::Production`, `SourceFile`, `ContextMap`, `TestTracker` | 2.8 | 47 |
| `SimpleCov::CLI::Diff` | 2.0 | 30 |
| `SimpleCov` (the singleton), before scoping | 70.0 | 2.3 |
| `SimpleCov` (the singleton), after scoping | 5.2 | 14.8 |

Mutant walks a subject's match expressions from most specific to least and takes the first that selects any test, so
a subject with no example named to it falls through to its namespace glob. For a subject on the singleton that glob
is the whole suite, because everything the library does passes through one module. Twenty-seven of the singleton's
54 subjects had no example of their own and were each pulling all 3,700, which is why the namespace took thirteen
minutes; scoping them took it to two. See item 6.

That the fall-through is silent is worth knowing on its own. An expression naming a subject that does not exist
matches nothing and reports nothing: five `SimpleCov::CLI` subjects were graded against the whole of `cli_spec.rb`
for months because the metadata spelled them `SimpleCov::CLI.run` where `extend self` makes them
`SimpleCov::CLI#run`. Check a new expression against `mutant environment subject list`.

### 1. Split the singleton into objects with their own lives

`SimpleCov` carries 54 subjects and `SimpleCov::Configuration`, mixed into the same singleton, carries 136. Between
them they are a sixth of the library's subjects on one object. Reading a setting, starting a run, coordinating
parallel workers, and deciding an exit status are all `SimpleCov.something`.

**Done without breaking.** The run's state lives on `SimpleCov::CurrentRun` (see item 3), and the singleton keeps
its whole surface by delegating to it through generated forwarders, which mutation analysis does not measure. The
run's behaviour is a `CurrentRun` question with a pool of its own.

**What remains, and why it breaks.** The lifecycle itself (start, finish, and the configuration a run reads) still
passes through the singleton. Moving it onto the run object and passing configuration in, with `SimpleCov.start`
delegating, changes what the at_exit machinery and every subclassing formatter may hold a reference to.

### 2. Separate reading a setting from writing it

Configuration methods are their own readers and writers, distinguished by a sentinel:

```ruby
def color(value = :__no_arg__)
  return instance_variable_defined?(:@color) ? @color : :auto if value.eql?(:__no_arg__)

  @color = value
end
```

One method, two behaviours, and a sentinel comparison that is itself a mutation surface. Every such method needs its
read path, its write path, and its default all pinned, and 136 subjects are shaped this way.

**Done without breaking.** Every dual-purpose setting has an explicit writer: `SimpleCov.color = :never`,
`SimpleCov.merge_timeout = 300`, and fifteen more. The writer holds the whole write behaviour (expansion,
validation, cache invalidation) and the dual method's write arm delegates to it, so the behaviour lives once.

**What remains, and why it breaks.** The dual spelling itself, sentinel and all: retiring `SimpleCov.color(:never)`
in favour of the writer, with the DSL block keeping the bare-word spelling by evaluating against a builder, changes
what configuration files may say.

### 3. Make process state explicit rather than global

The run's state lives in instance variables on the singleton: `@result`, `@running`, `@pid`, `@current`. Specs reset
them by hand, and several examples in this suite reach for `instance_variable_set` and `remove_instance_variable` to
get a clean slate. State that has to be un-set by hand is state that leaks between examples, which is what makes a
mutation look killed when the previous example is what killed it.

**Done without breaking.** The state lives on `SimpleCov::CurrentRun`, and a new run is a new object:
`start_tracking` begins a successor that carries only the fork genealogy (a forked child must not forget it was
forked, and a parent must not recount its subprocess serials). Examples that shepherded five instance variables
through around hooks now swap one run object in and out, and one cross-example leak of exactly the kind this item
describes died in the move.

**What remains, and why it breaks.** `@exit_exception` and the at_exit installation flag stay process-global on the
singleton, and the run object is internal. Exposing it as API is the item-1 remainder.

### 4. Return violations instead of printing them

The exit checks compute a violation and print it in the same method:

```ruby
def report_violation(violation)
  ExitCodes.print_error format("%<criterion>s coverage (%<actual>s) is below ...", ...)
end
```

Testing the message means capturing stderr, and every check's message needed its own capture to pin. Nothing was
wrong with the messages, but nothing could see them either: before this work every one of them could be rewritten to
name a different criterion, a different file, or nothing at all, and the suite still passed.

**Done without breaking.** Checks answer `violations` and `report_lines` as public values, each check renders its
violations into lines, and printing happens in one place, the base class's `report`. Every message assertion in the
check specs holds a value instead of capturing stderr. `ExitCodeHandling.call` kept its signature and behaviour.

**What remains.** Nothing that needs a major version: the check classes are internal, so this item is done.

### 5. Make the exit path callable without exiting

The whole at-exit path is only observable by running a real project in a child process, which is what the 128 sandbox
examples do. Those examples are worth having and they are the slowest thing in the suite, and **they can never kill a
mutation**: mutant mutates the parent in memory, and the child loads the file from disk unmutated. They are now
tagged `mutant: false` so mutation analysis stops considering them, which is honest about what they can prove.

**Done without breaking.** `SimpleCov.run_exit_tasks` does everything the end of a measured run does and answers
the exit status the process should end with; `run_exit_tasks!` is the exiting adapter over it, with the one
`Kernel.exit`. Every branch of the path is pinned by in-process examples that hold the status as a value and assert
the process was never ended.

**What remains.** Nothing that needs a major version: the sandbox suite still proves the wiring end to end, but the
behaviour it wires is now answerable in process, so this item is done.

### 6. Give every spec block a subject expression (done)

Not an API change, and the largest single lever there was. Every block in `spec/simplecov_spec.rb` now carries
`mutant_expression:` metadata naming the subjects it covers, and so do the blocks covering the `SimpleCov::CLI`
module itself. The namespace selects 276 tests where it used to select 3,780.

It also told the truth. Scoping `SimpleCov.start` took it from 3,631 selected tests to 4, and from an apparent 100%
to 69.56%: the difference was mutations killed by unrelated examples that happened to call `start` on their way to
somewhere else. Across the namespace the honest figure was 85.47% against an apparent 100%, and closing that gap is
what the examples added alongside the metadata are for. A number that depends on what the rest of the suite
incidentally touches is not a measurement of these tests.

**How to keep it.** `mutant_expression:` metadata naming the exact subjects, on each block, checked against
`mutant environment subject list`. See [Contributing](Contributing.md) for how mutant derives a pool when the
metadata is absent.

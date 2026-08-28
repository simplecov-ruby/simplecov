# Mutation testing roadmap

The API changes that would make this library faster and easier to hold to account, and why each one costs a major
version.

*Part of the [SimpleCov](../README.md) documentation.*

## Mutation testing roadmap

The suite is measured by [mutant](https://github.com/mbj/mutant) at the full operator set, and getting there taught
us where the library's shape fights the tool. None of what follows is required to keep mutation coverage at 100%: it
is all already there. What follows would make holding it there quicker to run and cheaper to maintain, and every
item needs a major version because it changes what callers may say.

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

**Breaking change.** Move the run's lifecycle to an object (`SimpleCov::Run` or similar) that is created, started and
finished, and pass configuration to it rather than reading it from a global. `SimpleCov.start` stays as the front
door and delegates.

**What it buys.** A spec can name the object it exercises, so its subjects select the examples about them and nothing
else. On the evidence above that is the difference between a namespace measuring in two hours and in under a minute.

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

**Breaking change.** `SimpleCov.color` reads; `SimpleCov.color = value` writes. The DSL block keeps the bare-word
spelling by evaluating against a builder, which is where a DSL should have lived anyway.

**What it buys.** Half as many behaviours per subject, no sentinel to compare, and the default becomes a value that
can be asserted rather than a branch that has to be reached.

### 3. Make process state explicit rather than global

The run's state lives in instance variables on the singleton: `@result`, `@running`, `@pid`, `@current`. Specs reset
them by hand, and several examples in this suite reach for `instance_variable_set` and `remove_instance_variable` to
get a clean slate. State that has to be un-set by hand is state that leaks between examples, which is what makes a
mutation look killed when the previous example is what killed it.

**Breaking change.** Hold the state on the run object from item 1, and let a new run be a new object.

**What it buys.** Examples stop resetting globals, which removes a class of order dependence. Two order-dependent
failures found during this work were of exactly that kind.

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

**Breaking change.** Checks answer structured violations; a reporter renders them. `SimpleCov::ExitCodes.call` keeps
its signature and does both.

**What it buys.** Assertions on values rather than on captured output, and one place to test rendering instead of
eight.

### 5. Make the exit path callable without exiting

The whole at-exit path is only observable by running a real project in a child process, which is what the 128 sandbox
examples do. Those examples are worth having and they are the slowest thing in the suite, and **they can never kill a
mutation**: mutant mutates the parent in memory, and the child loads the file from disk unmutated. They are now
tagged `mutant: false` so mutation analysis stops considering them, which is honest about what they can prove.

**Breaking change.** Make the exit behaviour a call that returns a status and performs no side effect of its own, so
`at_exit` becomes a one-line adapter over something testable in process.

**What it buys.** The behaviour that decides every user's build status becomes answerable in process, where a
mutation to it can actually be caught.

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

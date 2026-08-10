# Formatters and output

The bundled HTML and JSON formatters, third-party formatters, the coverage.json schema, and output diagnostics.

*Part of the [SimpleCov](../README.md) documentation.*

## Formatters

### Using your own formatter

```ruby
SimpleCov.formatter = SimpleCov::Formatter::HTMLFormatter
```

`SimpleCov.result.format!` instantiates a configured formatter class, then calls `#format(result)`, where `result` is a
`SimpleCov::Result`. A ready-built formatter instance receives `#format` directly, which lets constructor options carry
through to report generation. Do whatever you wish with it.

### Passing options to formatters

Anywhere a formatter class is accepted, a ready-built instance works too — that's how you reach constructor options.
The built-in HTML and JSON formatters take `silent: true` to suppress the "Coverage report generated" status line on
stderr, and `output_dir:` to write the report somewhere other than `SimpleCov.coverage_path`:

```ruby
SimpleCov.start do
  formatter SimpleCov::Formatter::HTMLFormatter.new(silent: true)
end
```

Instances mix freely with classes in `formatters` lists as well.

### Using multiple formatters

As of SimpleCov 0.9 you can specify multiple result formats. The HTML and JSON formatters are built in; other
formatters ship as separate gems you'll need to add and require — for example,
[simplecov-cobertura](https://github.com/dashingrocket/simplecov-cobertura) for the Cobertura XML that many CI services
consume.

```ruby
require "simplecov-cobertura"

SimpleCov.formatters = [
  SimpleCov::Formatter::HTMLFormatter,
  SimpleCov::Formatter::CoberturaFormatter,
]
```

### JSON formatter

`SimpleCov::Formatter::JSONFormatter` emits JSON — useful for CI consumption or reporting to external services.

```ruby
SimpleCov.formatter = SimpleCov::Formatter::JSONFormatter
```

By default `coverage.json` carries the full source-text array for every file, which makes the payload self-contained
but dominates the file size on larger projects. Tools that read the project's source files directly from disk can opt
out of that field with:

```ruby
SimpleCov.start do
  source_in_json false
end
```

The HTML report always retains the source array in its embedded data — the client-side viewer renders source from
there. The setting only affects the side-file `coverage.json`. When the source is omitted, `meta.commit` (the git
commit SHA the report was generated against) lets tools recover the exact source lines from repository history.

> The JSON formatter was originally a separate gem,
> [simplecov_json_formatter](https://github.com/codeclimate-community/simplecov_json_formatter). It is now built in and
> loaded by default; existing code that does `require "simplecov_json_formatter"` will continue to work.

### JSON Schema for `coverage.json`

`coverage.json` is a public contract, described by a JSON Schema (2020-12) so downstream tools can validate it,
generate types, or pin to a known shape. Every emitted document carries a top-level `$schema` URL pointing at the
versioned canonical, plus a human-readable `meta.schema_version` (`"major.minor"`).

The **versioned canonical** lives at [`schemas/coverage-v1.0.schema.json`](../schemas/coverage-v1.0.schema.json) and
long-lived integrations should pin to it. Once a SimpleCov release ships with a given versioned schema file, that file
is immutable: bug fixes, additions, or shape changes ship as a new versioned file (a minor or major bump), never as a
silent rewrite of an already-released one. Schemas may still be corrected in-place between gem releases — i.e., the
schema file as it currently exists on `main` may change before the next gem release, but the schema for any published
gem version stays frozen. A convenience alias at [`schemas/coverage.schema.json`](../schemas/coverage.schema.json) always
tracks the latest and may shift when a new SimpleCov release bumps the schema.

The schema version is independent of the gem version:

- Additive changes (new fields) bump the **minor** segment. Existing consumers keep working.
- Removals or shape changes bump the **major** segment, and ship as a new `schemas/coverage-vX.0.schema.json` file so
  v1.x consumers stay valid.

The current version is **1.0**. Top-level structure:

```jsonc
{
  "$schema":  "https://raw.githubusercontent.com/simplecov-ruby/simplecov/main/schemas/coverage-v1.0.schema.json",
  "meta":     { /* schema_version, simplecov_version, command_name, project_name, timestamp, root, commit, line_coverage, branch_coverage, method_coverage */ },
  "total":    { /* aggregate stats for lines (and branches / methods when enabled) */ },
  "coverage": { "<project-relative path>": { /* per-file lines, source, branches, methods, etc. */ } },
  "groups":   { "<group name>": { /* per-group stats + files */ } },
  "errors":   { /* minimum_coverage, minimum_coverage_by_file, minimum_coverage_by_group, maximum_coverage, maximum_coverage_drop violations */ }
}
```

The `.resultset.json` file is **not** schema'd — it's SimpleCov-internal and may change shape across releases. Build
integrations on top of `coverage.json`.

### More formatters, editor integrations, and hosted services

  * [Open Source formatter and integration plugins for SimpleCov](Alternate_Formatters.md)
  * [Editor Integration](Editor_Integration.md)
  * [Hosted (commercial) services](Commercial_Services.md)

## Output and diagnostics

### Errors and exit statuses

If an error is raised, SimpleCov prints a message to `STDERR` with the exit status, to aid debugging:

```
SimpleCov failed with exit 1
```

Disable this message with:

```ruby
SimpleCov.print_errors false
```

### Color output

When color is enabled, SimpleCov highlights coverage percentages in its `STDERR` diagnostics by band (green for
`>= 90%`, yellow for `>= 75%`, red below) and prints the "SimpleCov failed with exit ..." summary in red. By default,
color is on only when `STDERR` is a TTY. Two environment variables override that:

- `NO_COLOR=1` (any non-empty value) disables color even when stderr is a TTY. Honors the
  [no-color.org](https://no-color.org) convention.
- `FORCE_COLOR=1` (any non-empty value) enables color even when stderr is not a TTY. Useful when stderr is piped through
  a wrapper that itself renders ANSI in a terminal (`parallel_tests --combine-stderr`, log multiplexers, some CI runners).

`NO_COLOR` wins if both are set.

For programmatic control, use `SimpleCov.color`. An explicit `true` or `false` wins over the env vars and TTY detection:

```ruby
SimpleCov.color true   # always on
SimpleCov.color false  # always off
SimpleCov.color :auto  # default behavior: NO_COLOR/FORCE_COLOR/TTY
```



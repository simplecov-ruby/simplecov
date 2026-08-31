# Compatibility and troubleshooting

Ruby and framework compatibility notes, common problems, and upgrade guidance.

*Part of the [SimpleCov](../README.md) documentation.*

## Compatibility and troubleshooting

### Ruby version compatibility

SimpleCov is built in [Continuous Integration] on Ruby 3.4+ and JRuby 10+. On CRuby, every coverage criterion
described above is available on the supported versions, including
[eval coverage](Configuration.md#eval-coverage), which JRuby does not implement.

### JRuby

On JRuby, only **line coverage** is available — branch, method, oneshot-line, and eval coverage rely on features of
CRuby's `Coverage` library that JRuby doesn't implement. SimpleCov detects this automatically: the bundled `strict`
profile, for instance, enforces only line coverage at 100% on JRuby instead of failing to load.

To get accurate line numbers in coverage results, JRuby needs its full backtrace enabled. Pass `JRUBY_OPTS="--debug"`,
or create a `.jrubyrc` with `debug.fullTrace=true`.

### Notes on specific frameworks and test utilities

Some frameworks and tools have quirks worth knowing about when using SimpleCov:

<table>
  <tr><th>Framework</th><th>Notes</th><th>Issue</th></tr>
  <tr>
    <th>
      parallel_tests
    </th>
    <td>
      As of 0.8.0, SimpleCov should correctly recognize parallel_tests and
      supplement your test suite names with their corresponding test env
      numbers. SimpleCov locks the resultset cache while merging, ensuring no
      race conditions occur when results are merged.
    </td>
    <td>
      <a href="https://github.com/simplecov-ruby/simplecov/issues/64">#64</a> &amp;
      <a href="https://github.com/simplecov-ruby/simplecov/pull/185">#185</a>
    </td>
  </tr>
  <tr>
    <th>
      knapsack_pro
    </th>
    <td>
      To make SimpleCov work with Knapsack Pro Queue Mode to split tests in parallel on CI jobs you need to provide CI node index number to the <code>SimpleCov.command_name</code> in <code>KnapsackPro::Hooks::Queue.before_queue</code> hook.
    </td>
    <td>
      <a href="https://knapsackpro.com/faq/question/how-to-use-simplecov-in-queue-mode">Tip</a>
    </td>
  </tr>
  <tr>
    <th>
      RubyMine
    </th>
    <td>
      The <a href="https://www.jetbrains.com/ruby/">RubyMine IDE</a> has
      built-in support for SimpleCov's coverage reports, though you might need
      to explicitly set the output root using `SimpleCov.root('foo/bar/baz')`
    </td>
    <td>
      <a href="https://github.com/simplecov-ruby/simplecov/issues/95">#95</a>
    </td>
  </tr>
  <tr>
    <th>
      Spork
    </th>
    <td>
      Because of how Spork works internally (using preforking), there used to
      be trouble when using SimpleCov with it, but that has apparently been
      resolved with a specific configuration strategy. See <a
      href="https://github.com/simplecov-ruby/simplecov/issues/42#issuecomment-4440284">this</a>
      comment.
    </td>
    <td>
      <a href="https://github.com/simplecov-ruby/simplecov/issues/42#issuecomment-4440284">#42</a>
    </td>
  </tr>
  <tr>
    <th>
      Spring
    </th>
    <td>
      <a href="#using-spring-with-simplecov">See section below.</a>
    </td>
    <td>
      <a href="https://github.com/simplecov-ruby/simplecov/issues/381">#381</a>
    </td>
  </tr>
  <tr>
    <th>
      Test/Unit
    </th>
    <td>
      Test Unit 2 used to mess with ARGV, leading to a failure to detect the
      test process name in SimpleCov. <code>test-unit</code> releases 2.4.3+
      (Dec 11th, 2011) should have this problem resolved.
    </td>
    <td>
      <a href="https://github.com/simplecov-ruby/simplecov/issues/45">#45</a> &amp;
      <a href="https://github.com/test-unit/test-unit/pull/12">test-unit/test-unit#12</a>
    </td>
  </tr>
</table>

### Using Spring with SimpleCov

If you use [Spring](https://github.com/rails/spring) to speed up test runs, SimpleCov often misreports coverage with the
default config due to an eager-loading issue. There are a few fixes.

One solution is to [explicitly call eager
load](https://github.com/simplecov-ruby/simplecov/issues/381#issuecomment-347651728) in your `test_helper.rb` /
`spec_helper.rb` after calling `SimpleCov.start`:

```ruby
require 'simplecov'
SimpleCov.start 'rails'
Rails.application.eager_load!
```

Alternatively, disable Spring while running SimpleCov:

```sh
DISABLE_SPRING=1 rake test
```

Or remove `gem 'spring'` from your `Gemfile`.

### Different coverage between local and CI

Rails generates `config/environments/test.rb` with `config.eager_load = ENV["CI"].present?` (Rails 7+), so **CI eagerly
loads every file in `app/` while your local run does not**. The two environments then report different file sets and
different totals from the same suite. Two ways to make the report deterministic:

- Set `config.eager_load = true` everywhere in `test.rb` (slower locally, but matches CI — and matches what users
  actually see in production).
- Stick with the `rails` profile, which folds `{app,lib}/**/*.rb` into the report at 0% on every run regardless of
  `eager_load`. (The profile resolves the glob relative to `SimpleCov.root`, not the test runner's cwd.) Outside the
  profile, the equivalent is `cover "{app,lib}/**/*.rb"` — see the
  [legacy-API migration table](Configuration.md#migrating-from-the-legacy-configuration-api) for the relationship with the older
  `track_files`.

### Missing coverage

The **most common problem is that SimpleCov isn't required and started before everything else**. To track coverage for
your whole application, **SimpleCov must come first** so that it (and the underlying Coverage library) can track files
as they're loaded and used.

If coverage is missing for some code, a simple trick is to add a `puts` inside that file and another right after
`SimpleCov.start`, then check the order they print in:

```ruby
# my_code.rb
class MyCode

  puts "MyCode is being loaded!"

  def my_method
    # ...
  end
end

# spec_helper.rb / rails_helper.rb / test_helper.rb / .simplecov — whatever
SimpleCov.start
puts "SimpleCov started successfully!"
```

If you see this order, you're good:

```
SimpleCov started successfully!
MyCode is being loaded!
```

If `MyCode is being loaded!` prints first, the file was loaded before SimpleCov started — that's your problem.

### Upgrading from 0.x

Four methods that had been deprecated for a decade or more were removed in 1.0. Each had a one-to-one rename:

| Removed                                  | Use instead                                |
| ---------------------------------------- | ------------------------------------------ |
| `SimpleCov::Filter#passes?`              | `SimpleCov::Filter#matches?`               |
| `SimpleCov.adapters`                     | `SimpleCov.profiles`                       |
| `SimpleCov.load_adapter('rails')`        | `SimpleCov.load_profile('rails')`          |
| `SimpleCov::Formatter::MultiFormatter[]` | `SimpleCov::Formatter::MultiFormatter.new` |

If a custom filter still defines `passes?`, rename the method to `matches?` — the signature and semantics are identical.



[Continuous Integration]: https://github.com/simplecov-ruby/simplecov/actions?query=workflow%3Astable "SimpleCov is built around the clock by github.com"

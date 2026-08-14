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

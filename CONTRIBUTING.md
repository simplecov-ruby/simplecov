## Reporting Issues

You can report issues at https://github.com/colszowka/simplecov/issues

 * Search existing issues for your problem, chances are someone else already reported it.
 * Please make sure you are running the latest version of simplecov. If that is not possible, 
   please specify in your report why you can't update to the latest version.
 * Include the SimpleCov version you are running in your report.
 * Include your `ruby -e "puts RUBY_DESCRIPTION"`. Please also specify the gem versions of 
   Rails and your testing framework, if applicable.
   This is extremely important for narrowing down the cause of your problem.

Thanks!
   
## Making Contributions

To fetch & test the library for development, do:

    $ git clone https://github.com/colszowka/simplecov.git
    $ cd simplecov
    $ bundle
    $ rake appraisal:install
    $ rake appraisal

For more information on the appraisal gem (for testing against multiple gem dependency versions), please see
https://github.com/thoughtbot/appraisal/

If you want to contribute, please:

  * Fork the project.
  * Make your feature addition or bug fix.
  * Add tests for it. This is important so I don't break it in a future version unintentionally.
  * **Bonus Points** go out to anyone who also updates `CHANGELOG.md` :)
  * Send me a pull request on Github.

## Running Individual Tests

This project uses Test::Unit. Individual tests can be run like this:

```bash
ruby -I test path/to/test.rb
```

# Screenshot coverage project

This small RSpec project generates a screenshot-ready SimpleCov report for a
realistic Rails-style storefront. It uses SimpleCov's `rails` profile and puts
two files in each of the profile's seven groups, so the report has useful tabs
for Controllers, Channels, Models, Mailers, Helpers, Jobs, and Libraries.

From this directory, run:

```sh
bundle install
bundle exec rake
```

The task runs the specs, verifies the report shape, and writes the report to
`coverage/index.html`. On macOS, open it with:

```sh
open coverage/index.html
```

Line, branch, and method coverage are all enabled. Their percentages are
intentionally different, and line coverage still spans the useful visual bands
from 100% down to 0%. Exact hundredth-percent boundary values are not retained:
realistic files of roughly twenty lines cannot express ratios such as 90.01%.

The two controller files, the two channel files, and `orders_helper.rb` each
include one line-scoped exclusion for Rails logging. Open any of them in the
source view to see covered, missed, and skipped lines alongside missed branch
and method markers.

| Rails profile tab | Files |
| --- | --- |
| Controllers | `application_controller.rb`, `orders_controller.rb` |
| Channels | `application_cable/channel.rb`, `notifications_channel.rb` |
| Models | `application_record.rb`, `order.rb` |
| Mailers | `application_mailer.rb`, `receipt_mailer.rb` |
| Helpers | `application_helper.rb`, `orders_helper.rb` |
| Jobs | `application_job.rb`, `receipt_delivery_job.rb` |
| Libraries | `money_formatter.rb`, `order_number.rb` |

The Rails-like source tree is generated from `support/coverage_cases.rb` and is
ignored by Git along with the report. Re-running the task safely refreshes both.

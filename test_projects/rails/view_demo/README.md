# View coverage demo project

This small Rails project generates a report that shows `cover_views` in action.
It renders a storefront's templates from RSpec view specs with SimpleCov's
`rails` profile and branch coverage enabled, and its eight templates split
evenly: four are rendered by the specs and four are rendered by nothing, so the
report shows both halves of what view coverage does. ERB, Haml, and Slim each
appear on both sides of that divide.

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

Eval coverage is what measures templates, so this needs CRuby 3.2 or later.

## What to look at

The **Views** tab files all eight templates next to the Models tab, the way
Controllers and Models sit side by side in an app's report.

The rendered templates (`products/index.html.erb`, `carts/show.html.haml`, and
`account/summary.html.slim`) each mix the full vocabulary on their own line
numbers: covered lines with per-render hit counts, loop bodies with one hit per
iteration, missed lines, and covered and missed branch markers on their
conditionals. Each one deliberately leaves something unreached. The product
list is rendered without a promo message, the cart has no coupon, and the
account is not past due, so every rendered template points at a concrete
untested `if`.

The partial `products/_price.html.erb` is rendered once per product, so its
lines carry a hit count of 3, and one product being on sale reaches both arms
of its conditional.

The other four templates (`products/show.html.erb`,
`carts/abandoned.html.haml`, `account/closed.html.slim`, and the layout) are
rendered by no spec. Without `cover_views` they would be missing from the
report entirely. Instead they are compiled at the end of the run and appear at
0%, with real branch tuples for their conditionals. The layout is in this group
because view specs render templates without their layout.

Each template is highlighted in its own language in the source view, so the
markup reads as markup and the Ruby between the tags as Ruby.

What, why are there entire rails projects in here?

The reality is, this is the environment SimpleCov is used in most often.
To test the complex interactions interactions of different projects nothing beats the full and real thing.

Command to generate stripped down rails apps:

```
rails new --skip-action-mailer --skip-action-mailbox --skip-action-text --skip-active-storage --skip-action-cable --skip-javascript --skip-turbolinks --skip-sprockets --skip-git --skip-keep --skip-listen some_name
```

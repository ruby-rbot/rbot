# RBot - The Ruby IRC Bot

rbot is a ruby IRC bot. Think of him as a ruby bot framework with a highly
modular design based around plugins.

## Fork Changelog

- Drops ruby 1.8 support, ruby >= 1.9.3 is required.
- Ruby 2.1.0 is supported.
- Removes a lot of broken/outdated plugins.
- Removes the DRb remote interface due to its abysmal security.
- Introduces a [web service](https://github.com/4poc/rbot/wiki/Web-Service).
- Registry is now supporting DBM (that requires no external dependencies).

## Known Problems

* Ruby 2.0.0 (at least <=p353) is causing a segmentation fault crash that
only occurs after a few hours. This is [fixed](https://bugs.ruby-lang.org/issues/9168) in newer versions.

* DBM (if using Barkeley DB) is requiring manual repairs to work after
a crash.


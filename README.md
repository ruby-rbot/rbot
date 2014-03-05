# RBot - The Ruby IRC Bot

rbot is a ruby IRC bot. Think of him as a ruby bot framework with a highly
modular design based around plugins.

## Install Guide

Information about installing the bot can be found here: [Install-Guide](https://github.com/4poc/rbot/wiki/Install-Guide).

Notes on the registry and migrating from an old bot can be found here: [Registry-Migration-Notes](https://github.com/4poc/rbot/wiki/Registry-Migration-Notes).

## Fork Changes

- Ruby 2.1.1 is fully supported.
- Drops ruby 1.8 support, ruby >= 1.9.3 is required.
- Removes a lot of broken/outdated plugins.
- Removes the DRb remote interface due to its abysmal security.
- Introduces a [web service](https://github.com/4poc/rbot/wiki/Web-Service).
- Registry is now supporting DBM (that requires no external dependencies).
- [New standalone Backup/Restore Script](https://raw.github.com/4poc/rbot/fork/bin/rbotdb) for registry databases.
- Registry folders have now different names based on the adapter used: `~/.rbot/registry_<FORMAT>`
- Added a bundler `Gemfile` to make installing the dependecies easier.

## Known Problems

* Ruby 2.0.0 (at least <=p353) is causing a segmentation fault crash that
only occurs after a few hours. This is [fixed](https://bugs.ruby-lang.org/issues/9168) in newer versions of ruby.

* DBM (if using Barkeley DB, maybe other backends aswell) is requiring manual repairs to work after
a crash.

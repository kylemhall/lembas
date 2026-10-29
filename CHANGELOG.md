# Changelog

All notable changes to Lembas are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Short links for ByWater Solutions, replacing Polr: a random or a custom ending, and the same link when a URL is
  shortened again.
- Sign-in with Google, for bywatersolutions.com accounts only.
- A dashboard to shorten, search, edit, disable, delete and copy your links, with the clicks per day and the top
  referers of each link.
- API keys for scripts, shown once, which can be revoked at any time.
- A REST API described by OpenAPI at /api/v1, and the Polr API (/api/v2/action/shorten and lookup) for the scripts
  that already use it.
- An admin page listing every user and every link, where accounts can be disabled.
- An import of the Polr users, links, clicks and API keys, so every existing short link keeps working.

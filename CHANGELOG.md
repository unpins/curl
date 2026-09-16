# Changelog

## [Unreleased]

### Fixed

- The binary carried the manual pages of `wcurl` and `curl-config`, two
  commands it does not contain, so `unpin man curl wcurl` handed you the
  manual for something you cannot run. Only `curl`'s own page ships now.

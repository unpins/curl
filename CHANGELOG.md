# Changelog

## [Unreleased]

### Added

- **HTTP/3** on Linux and macOS. `curl --http3 https://…` negotiates QUIC, and
  `--http3-only` insists on it; the binary grows about 470 KiB. The Windows
  build keeps HTTP/2 as its ceiling — it uses the Windows certificate store for
  TLS, and that stack has no QUIC to build on.

### Fixed

- The binary carried the manual pages of `wcurl` and `curl-config`, two
  commands it does not contain, so `unpin man curl wcurl` handed you the
  manual for something you cannot run. Only `curl`'s own page ships now.

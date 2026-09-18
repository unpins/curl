# Changelog

## [Unreleased]

### Added

- **HTTP/3** on Linux and macOS. `curl --http3 https://…` negotiates QUIC, and
  `--http3-only` insists on it; the binary grows about 470 KiB. The Windows
  build keeps HTTP/2 as its ceiling — it uses the Windows certificate store for
  TLS, and that stack has no QUIC to build on.
- **WebSockets**: `ws://` and `wss://` URLs.
- **LDAP and LDAPS**: `curl 'ldap://host/dc=example,dc=com?cn?sub?(uid=me)'`.
- **SCRAM-SHA-1 and SCRAM-SHA-256** logins for IMAP, POP3 and SMTP
  (`--login-options AUTH=SCRAM-SHA-256`).
- **`curl --manual`** prints the full manual.

### Changed

- curl 8.21.0, fixing 18 of the 27 known vulnerabilities in 8.20.0.

### Fixed

- The binary carried the manual pages of `wcurl` and `curl-config`, two
  commands it does not contain, so `unpin man curl wcurl` handed you the
  manual for something you cannot run. Only `curl`'s own page ships now.

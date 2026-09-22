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
- The Windows binary is now built by the same compiler as the Linux and macOS
  ones. It is about 5% smaller (3.41 MB to 3.23 MB); `--version`, HTTP, HTTPS
  through the Windows certificate store, `file://` and an international domain
  name were checked under Wine.

  It now uses the Universal C Runtime, which is part of Windows 10 and later.
  On Windows 7 or 8.1 that runtime has to be installed first — it comes through
  Windows Update. The previous binary did not need it.

### Fixed

- The binary carried the manual pages of `wcurl` and `curl-config`, two
  commands it does not contain, so `unpin man curl wcurl` handed you the
  manual for something you cannot run. Only `curl`'s own page ships now.

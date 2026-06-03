# curl

Standalone build of [curl](https://curl.se/).

[![CI](https://github.com/unpins/curl/actions/workflows/curl.yml/badge.svg)](https://github.com/unpins/curl/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) project — native single-binary builds with no third-party runtime dependencies.

## Usage

Run the `curl` program with [unpin](https://github.com/unpins/unpin):

```bash
unpin curl https://example.com
unpin curl -LO https://example.com/file.tar.gz   # download to a file
```

To install it onto your PATH:

```bash
unpin install curl
```

## Build locally

```bash
nix build github:unpins/curl
./result/bin/curl
```

Or run directly:

```bash
nix run github:unpins/curl
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/curl/releases) page has standalone binaries for manual download.

## Build notes

### TLS

- **Linux / macOS use OpenSSL** with an **embedded Mozilla CA bundle** baked in via curl's `--with-ca-embed` (curl 8.5+). The embed is the **default trust store** — curl uses it whenever you don't pass `--cacert` / `--capath` (or set `$CURL_CA_BUNDLE` / `$SSL_CERT_FILE`). The compile-time `--with-ca-bundle` path is *not* consulted by the curl CLI at runtime, so HTTPS works identically on Debian, scratch containers, busybox-init, or freshly-installed BSDs. To trust roots installed via your distro's `update-ca-certificates` (e.g. a corporate root), point curl at the host bundle explicitly: `curl --cacert /etc/ssl/certs/ca-certificates.crt …` or `export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt`. Roughly +454 KB binary size.
- **Windows uses Schannel** (the OS-native TLS stack) instead of OpenSSL. Schannel reads roots from the Windows certificate store via `CertOpenSystemStoreW`, so there's no bundle to ship; users manage trust through Windows itself. As a side effect, no `--cacert` workflow on Windows — use `certutil` / Group Policy.

### Disabled (conscious)

- **HTTP/3** — off everywhere. Needs `quictls` (a BoringSSL/ngtcp2-friendly OpenSSL fork) plus `ngtcp2` + `nghttp3`. Not in nixpkgs.
- **SCP / SFTP (libssh2)** — off on Windows only. libssh2 needs a crypto backend (OpenSSL / mbedTLS / wolfSSL); with Schannel as our TLS stack there's nothing for libssh2 to link against. Microsoft's own bundled `curl.exe` ships without SSH either. Linux / macOS keep `scp://` and `sftp://`.

### Disabled (inherited from nixpkgs default; we don't override)

These are off in nixpkgs's `curl.nix` defaults; we made no case for re-enabling them:

- **LDAP / LDAPS** — pulls OpenLDAP + cyrus-sasl chain; almost no one queries LDAP via curl.
- **WebSockets (`ws://`, `wss://`)** — still labeled experimental by upstream; nixpkgs doesn't pass `--enable-websockets`.
- **GSS-API / Kerberos / SPNEGO** — would pull MIT krb5 or Heimdal; corporate-AD-on-Linux niche.
- **RTMP** — librtmp is an obsolete Flash streaming protocol; even upstream defaults off.
- **libgsasl** — extended SASL mechanisms (OAUTHBEARER, SCRAM-SHA-256) for SMTP/IMAP; curl's built-in SASL covers PLAIN/LOGIN/CRAM-MD5/DIGEST/NTLM which is what most users hit.
- **`--manual`** — curl's built-in `curl --manual` text (~70 KB baked into the binary) is off. The man page itself is still embedded via unpins' `withMan` (the `.unpin_man` block — `unpin man curl`).
- **MultiSSL** — only relevant to libcurl-as-library consumers picking a TLS backend at runtime; CLI doesn't use it.

Open an issue if any of these block real usage; we'll reassess.

### Tests

`doCheck` is off — verified by running the suite, not assumed:

- curl's autotools `make check` is a **no-op** (it builds the test apps but runs zero tests — `Nothing to be done for 'check'`). The real suite is `make test` (`tests/runtests.pl`, which spins up local HTTP/FTP/… servers; the server stack does come up fine in the build sandbox).
- The full `make test` reports **1610 / 1638 OK (98 %)**, but every one of the ~28 failures is caused by *our own* `--with-ca-embed`: curl prints an extra `Note: Using embedded CA bundle …` line on stderr that upstream's stock-build test expectations don't carry. Those are not curl defects or musl issues, so a clean gate would need a version-fragile per-test ignore-list. `curl --version` is the smoke floor.

### wcurl

Upstream also ships `wcurl`, a 352-line POSIX-sh download wrapper (`wcurl URL` → curl with download-friendly defaults plus RFC 3986 filename decoding). We don't ship it: as installed it's a second executable carrying a `/nix/store` shell shebang — a closure dependency that can't run on a user's machine and breaks the single-binary promise.

**TODO:** port wcurl from shell to C and fold it into a `curl` multicall — an `argv[0]`-dispatched applet embedded as a UNPIN_META alias (the coreutils/busybox pattern), so the convenience lives inside the one static binary on every platform. Until then, the common case is a one-line shell alias:

```sh
wcurl() { curl -LO --remote-time --retry 5 --continue-at - "$@"; }
```

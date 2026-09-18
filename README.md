# curl

[curl](https://curl.se/) as a single self-contained binary, built natively for Linux, macOS, and Windows.

[![CI](https://github.com/unpins/curl/actions/workflows/curl.yml/badge.svg)](https://github.com/unpins/curl/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) catalog; install it with [`unpin`](https://github.com/unpins/unpin): `unpin install curl`.

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

- **Linux / macOS use OpenSSL** with an **embedded Mozilla CA bundle** baked in via curl's `--with-ca-embed` (curl 8.5+). The embed is the **default trust store** — used whenever you don't pass `--cacert` / `--capath` (or set `$CURL_CA_BUNDLE` / `$SSL_CERT_FILE`) — so HTTPS works identically on Debian, scratch containers, busybox-init, or freshly-installed BSDs. To trust roots installed via your distro's `update-ca-certificates` (e.g. a corporate root), point curl at the host bundle: `curl --cacert /etc/ssl/certs/ca-certificates.crt …` or `export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt`. Roughly +454 KB binary size.
- **Windows uses Schannel** (the OS-native TLS stack) instead of OpenSSL. Schannel reads roots from the Windows certificate store via `CertOpenSystemStoreW`, so there's no bundle to ship; users manage trust through Windows itself. As a side effect, no `--cacert` workflow on Windows — use `certutil` / Group Policy.

### HTTP/3

- **On for Linux and macOS**, through ngtcp2 and nghttp3 over the same OpenSSL the rest of the build uses. `curl --http3 https://…` negotiates QUIC and falls back to HTTP/2 if it can't; `--http3-only` refuses to fall back. Costs about 470 KiB of binary.
- **Off on Windows**, and not by preference. The Windows build gets its TLS from Schannel so that it can read roots from the Windows certificate store (see above), and Schannel offers no QUIC — curl's own configure rejects the pair outright. Having HTTP/3 there would mean switching Windows to OpenSSL and shipping a CA bundle with it, trading the OS trust store for one protocol version. Windows tops out at HTTP/2.

### Disabled (conscious)

- **SCP / SFTP (libssh2)** — off on Windows only. libssh2 needs a crypto backend (OpenSSL / mbedTLS / wolfSSL); with Schannel as our TLS stack there's nothing for libssh2 to link against. Microsoft's own bundled `curl.exe` ships without SSH either. Linux / macOS keep `scp://` and `sftp://`.
- **GSS-API / Kerberos / SPNEGO** — off on Linux and macOS. MIT krb5 does not link into a static binary, so the static curl drops it; the ordinary dynamic curl has all three. The Windows build does have them, through Windows' own SSPI rather than krb5.

### Also on

The stock nixpkgs curl leaves these out; this build turns them on:

- **WebSockets** — `ws://` and `wss://`. Part of curl's default build since 8.11.
- **LDAP / LDAPS** — `ldap://` and `ldaps://` queries. Windows uses the system's own LDAP client, which always signs in: as the current Windows user (right for Active Directory), or as the account you give with `-u`. It has no anonymous query, so other servers need `-u`.
- **libgsasl** — SCRAM-SHA-1 and SCRAM-SHA-256 logins for IMAP, POP3 and SMTP, on top of curl's built-in PLAIN, LOGIN, CRAM-MD5, DIGEST-MD5, NTLM and OAUTHBEARER.
- **`curl --manual`** — the full manual, printed by the binary itself.

Still off:

- **RTMP** — curl removed it in 8.20; there is nothing left to enable.
- **MultiSSL** — lets a program linking libcurl pick a TLS library at run time; the command line has one TLS library and no use for the choice.

### Tests

`doCheck` is off — verified by running the suite, not assumed:

- curl's autotools `make check` is a **no-op** (builds the test apps but runs zero tests). The real suite is `make test` (`tests/runtests.pl`, which spins up local HTTP/FTP/… servers — that stack does come up fine in the build sandbox).
- The full `make test` reports **1610 / 1638 OK (98 %)**, and every one of the ~28 failures is caused by *our own* `--with-ca-embed`: curl prints an extra `Note: Using embedded CA bundle …` line on stderr that upstream's stock-build expectations don't carry. Those aren't curl defects or musl issues, so a clean gate would need a version-fragile per-test ignore-list. `curl --version` is the smoke floor.

### wcurl

Upstream also ships `wcurl`, a POSIX-sh download wrapper (`wcurl URL` → curl with download-friendly defaults). We don't ship it: as installed it carries a `/nix/store` shell shebang — a closure dependency that can't run on a user's machine and breaks the single-binary promise.

The common case is a one-line shell alias:

```sh
wcurl() { curl -LO --remote-time --retry 5 --continue-at - "$@"; }
```

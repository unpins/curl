# curl

Standalone build of [curl](https://curl.se/).

[![CI](https://github.com/unpins/curl/actions/workflows/curl.yml/badge.svg)](https://github.com/unpins/curl/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) project — native single-binary builds with no third-party runtime dependencies.

## Installation

Install with [unpin](https://github.com/unpins/unpin):

```bash
unpin curl
```

Or run without installing:

```bash
unpin run curl
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

The [Releases](https://github.com/unpins/curl/releases) page has standalone binaries and a `.tar.zst` data archive (man pages and completions) for manual download.

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
- **`--manual`** — would embed the manpage in the binary (~70 KB); we ship the manpage in the `.tar.zst` instead.
- **MultiSSL** — only relevant to libcurl-as-library consumers picking a TLS backend at runtime; CLI doesn't use it.

Open an issue if any of these block real usage; we'll reassess.

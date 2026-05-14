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

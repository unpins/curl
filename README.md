# curl

Standalone build of [curl](https://curl.se/).

Part of the [unpins](https://unpins.org) project — single-binary, statically-linked builds that run on any Linux, macOS or Windows without external dependencies.

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

The [Releases](https://github.com/unpins/curl/releases) page has standalone binaries for manual download.

{
  description = "Standalone build of curl";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "curl";

      # Smoke floor: `curl --version` on every native ABI + the Windows
      # runner. `libcurl/` is in the version banner on all backends (OpenSSL
      # and Schannel alike). This is the only runtime check we keep — the
      # upstream suite is documented-off (see README "Tests").
      smoke = [ "--version" ];
      smokePattern = "libcurl/";

      # Native feature set:
      #   openssl + zlib + nghttp2 + libssh2 + libidn2 + libpsl
      #   + brotli + zstd — taken from `pkgs.curl` defaults.
      #   http3 OFF: needs quictls-patched openssl.
      #
      # Embed the Mozilla CA bundle via curl's --with-ca-embed (8.5+).
      # The embed is the default trust store: the curl CLI uses it
      # whenever neither --cacert/--capath nor $CURL_CA_BUNDLE /
      # $SSL_CERT_FILE is set (see src/config2setopts.c). The
      # compile-time --with-ca-bundle path is NOT consulted at
      # runtime. To trust host-installed roots (e.g. corp CA via
      # update-ca-certificates), users explicitly pass --cacert or
      # set CURL_CA_BUNDLE. ~454KB cost.
      #
      # `--disable-shared` is critical on darwin: pkgsStatic.curl on
      # darwin still produces a `libcurl.4.dylib` and libtool prefers
      # shared, so the `curl` binary ends up dynamically linked against
      # it (single-binary policy violation). Linux pkgsStatic suppresses
      # this automatically; darwin doesn't.
      #
      # Quirk: `nix-lib`'s `filterEnableStaticOnDarwin` strips
      # `--disable-shared` from `configureFlags` on darwin to avoid
      # `--enable-static` translating into `LDFLAGS="-static"` and
      # breaking later AC_CHECK_LIB probes. To re-inject the flag
      # *after* that filter we push it via `configureFlagsArray` in
      # `preConfigure` — that bash array is appended at configure-time
      # and is invisible to Nix-list filtering.
      build = pkgs:
        (pkgs.pkgsStatic.curl.override { http3Support = false; }).overrideAttrs (old: {
          configureFlags = (old.configureFlags or [ ]) ++ [
            "--with-ca-embed=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          ];
          preConfigure = (old.preConfigure or "") + ''
            configureFlagsArray+=("--disable-shared")
          '';
          # curl 8.8+ also installs `wcurl`, a POSIX-sh download wrapper. It
          # lands in bin/ as a *script* with a `/nix/store/...-bash` shebang —
          # a second executable AND a store-closure dependency that can't run
          # on a user's machine. Drop it; we ship one self-contained `curl`.
          postInstall = (old.postInstall or "") + ''
            rm -f "''${bin:-$out}/bin/wcurl"
          '';
        });

      # Windows feature set:
      #   Schannel (Windows native TLS, no CA bundle to ship) instead
      #   of OpenSSL; libssh2 disabled (needs a crypto backend).
      #   Microsoft's own curl.exe also ships without scp.
      windowsBuild = pkgs: ulib.mingwStaticBinary {
        pkg = (ulib.mingwStaticCross pkgs).curl;
        staticDeps = {
          opensslSupport = false;
          scpSupport     = false;
          http3Support   = false;
        };
        # curl.nix injects --without-ssl when opensslSupport=false;
        # we're enabling Schannel instead.
        filterConfigureFlag = f: f != "--without-ssl";
        extraConfigureFlags = [ "--with-schannel" ];
        extraCFlags = [ "-DNGHTTP2_STATICLIB" "-DCURL_STATICLIB" "-DPSL_STATIC" ];
        # Drop the `wcurl` sh wrapper here too (see native build): a unix
        # shell script next to curl.exe is dead weight on Windows.
        extraOverrides = old: {
          postInstall = (old.postInstall or "") + ''
            rm -f "''${bin:-$out}/bin/wcurl"
          '';
        };
      };
    };
}

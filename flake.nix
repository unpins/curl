{
  description = "curl as a single self-contained binary";

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
      dnsFallback = true; # resolves hostnames; opt into the Android DNS fallback
      name = "curl";

      # Smoke floor: `curl --version` on every native ABI + the Windows
      # runner. `libcurl/` is in the version banner on all backends (OpenSSL
      # and Schannel alike). This is the only runtime check we keep — the
      # upstream suite is documented-off (see README "Tests").
      smoke = [ "--version" ];
      smokePattern = "libcurl/";

      # Engine (no multicall — single binary): build curl with the unpin-llvm
      # engine so it links the SAME engine-built openssl/zlib/nghttp2/… closure
      # the rest of the catalog converges on (openssl/dnsutils already migrated).
      # useEngine kicks in on linux/darwin; Windows keeps useEngine=false → plain
      # mingw pkgs (windowsBuild below, not yet on the engine).
      engine = "unpin-llvm";

      # libpsl compiles the public-suffix list in as a builtin DAFSA (the
      # `.DAFSA@PSL_` blob in the binary), and curl resolves it via psl_builtin()
      # / psl_latest(NULL) — which falls back to the builtin when the dist file is
      # absent. So the compile-time `…/publicsuffix-list…/public_suffix_list.dat`
      # path baked into libpsl is a DEAD string the running binary never opens;
      # scrub it so the shipped binary keeps 0 store references. (The pre-engine
      # build carried this same vestigial ref; tier-3 fixes it rather than keeping
      # the status quo.)
      removeReferences = [ "publicsuffix-list" ];

      # Native feature set:
      #   openssl + zlib + nghttp2 + libssh2 + libidn2 + libpsl
      #   + brotli + zstd — taken from `pkgs.curl` defaults.
      #
      # HTTP/3 is on. It was off here for a reason that stopped being true:
      # HTTP/3 once needed the `quictls` fork of OpenSSL, and nixpkgs now
      # builds ngtcp2 + nghttp3 against stock OpenSSL. Measured: +481 KB, still
      # 0 store references, and `--http3` gets a real HTTP/3 response
      # (%{http_version} = 3) from cloudflare-quic.com.
      #
      # Two of the advisories open against 8.20.0 are HTTP/3-only, which makes
      # the version bump a release blocker for this build specifically: turning
      # the feature on is what makes those two reachable. Bump before tagging.
      #
      # The Windows build below stays without it — see the note there.
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
        (pkgs.pkgsStatic.curl.override {
          http3Support = true;
          websocketSupport = true;
          ldapSupport = true;
          gsaslSupport = true;
        }).overrideAttrs (old: {
          # nixpkgs hardcodes `--disable-manual`; `curl --manual` is part of
          # the program, so turn it back on. `gsaslSupport` only adds the
          # library, and curl's configure leaves it out unless asked; the
          # option is `--with-libgsasl` (curl's own summary line suggests a
          # `--with-gsasl` that configure rejects as unknown).
          configureFlags = builtins.filter (f: f != "--disable-manual") (old.configureFlags or [ ]) ++ [
            "--enable-manual"
            "--with-libgsasl"
            "--with-ca-embed=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          ];
          preConfigure = (old.preConfigure or "") + ''
            configureFlagsArray+=("--disable-shared")
          '';
          # curl 8.8+ also installs `wcurl`, a POSIX-sh download wrapper. It
          # lands in bin/ as a *script* with a `/nix/store/...-bash` shebang —
          # a second executable AND a store-closure dependency that can't run
          # on a user's machine. Drop it; we ship one self-contained `curl`.
          #
          # Their man pages go with them. withMan embeds the WHOLE man output,
          # so leaving them behind ships `unpin man curl wcurl` and
          # `unpin man curl curl-config` — manuals for two commands this binary
          # does not have. (`curl-config` is a libcurl build helper nixpkgs
          # moves to the dev output, so it never reaches the artifact either.)
          postInstall = (old.postInstall or "") + ''
            rm -f "''${bin:-$out}/bin/wcurl"
            rm -f "''${man:-$out}"/share/man/man1/wcurl.1* \
                  "''${man:-$out}"/share/man/man1/curl-config.1*
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
          # No HTTP/3 here, and it is not a knob we are declining to turn:
          # measured with it on, curl's configure stops the build with
          # "the detected TLS library does not support QUIC, making
          # --with-ngtcp2 a no-no". Schannel has no QUIC, and ngtcp2 needs a
          # crypto backend that does — nixpkgs happily cross-builds ngtcp2 and
          # nghttp3 for mingw, so the eval and the dependency closure both look
          # fine right up to configure. Enabling it means moving Windows off
          # Schannel onto OpenSSL, which costs the Windows certificate store
          # and gains one protocol version. Not a trade worth making.
          http3Support   = false;
          websocketSupport = true;
          gsaslSupport   = true;
          # ldapSupport stays false: it would cross-build OpenLDAP, while
          # curl's configure reaches Windows' own wldap32 by itself once
          # LDAP is enabled (below).
        };
        # curl.nix injects --without-ssl when opensslSupport=false;
        # we're enabling Schannel instead.
        filterConfigureFlag = f: !(builtins.elem f [
          "--without-ssl" "--disable-ldap" "--disable-ldaps" "--disable-manual"
        ]);
        extraConfigureFlags = [
          "--with-schannel" "--enable-ldap" "--enable-ldaps" "--enable-manual"
          "--with-libgsasl"
        ];
        extraCFlags = [ "-DNGHTTP2_STATICLIB" "-DCURL_STATICLIB" "-DPSL_STATIC" ];
        # libgsasl's SCRAM runs passwords through SASLprep, which lives in
        # libidn. The static archive's `.pc` says so under `Libs.private`, but
        # curl's configure asks pkg-config for `--libs-only-l` without
        # `--static`, so its `gsasl_init` probe links a bare `-lgsasl`, fails,
        # and curl quietly builds without gsasl.
        extraInputs = [ (ulib.mingwStaticCross pkgs).libidn ];
        # Drop the `wcurl` sh wrapper here too (see native build): a unix
        # shell script next to curl.exe is dead weight on Windows.
        extraOverrides = old: {
          preConfigure = (old.preConfigure or "") + ''
            export LIBS="''${LIBS:+$LIBS }-lidn"
          '';
          postInstall = (old.postInstall or "") + ''
            rm -f "''${bin:-$out}/bin/wcurl"
            rm -f "''${man:-$out}"/share/man/man1/wcurl.1* \
                  "''${man:-$out}"/share/man/man1/curl-config.1*
          '';
        };
      };
    };
}

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

      # ---------------------------------------------------------------------
      # Curl-specific helper. Not in nix-lib because curl is the only
      # consumer so far — promote if a second libpsl consumer appears.
      #
      # Make libpsl usable as a static lib by curl's autoconf probe.
      # Two things go wrong by default:
      #   - libpsl.pc keeps the transitive libs in Libs.private, but curl
      #     reads via `pkg-config --libs-only-l libpsl` which only honors
      #     Libs:. Promote them.
      #   - The merged Libs: order matters because static linking is a
      #     single left-to-right pass: a lib's symbols only get pulled in
      #     to satisfy *already-undefined* refs. libidn2 (consumer) must
      #     precede libunistring (provider); same for libpsl/libidn2.
      #     Rewrite Libs: with the right ordering.
      # Also propagate libunistring/libiconv since libpsl declares them as
      # plain buildInputs; without that, the consumer (curl) won't see -L
      # paths for them and ld bails on -lunistring.
      # ---------------------------------------------------------------------
      libpslStaticFix = libunistring: libiconv: drv: drv.overrideAttrs (old: {
        propagatedBuildInputs = (old.propagatedBuildInputs or [])
          ++ [ libunistring libiconv ];
        postFixup = (old.postFixup or "") + ''
          pc="$dev/lib/pkgconfig/libpsl.pc"
          if [ -f "$pc" ]; then
            sed -i '/^Libs:/c\
Libs: -L''${libdir} -L${libunistring}/lib -L${libiconv}/lib -lpsl -lidn2 -lunistring -liconv -lws2_32
' "$pc"
          fi
        '';
      });
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "curl";

      # Native build feature set:
      #   openssl + zlib + nghttp2 (http2) + libssh2 (scp/sftp)
      #     — inherited from curlMinimal defaults
      #   + libidn2, libpsl, brotli, zstd
      #     — added by `pkgs.curl` over `curlMinimal`
      #   - http3 OFF: needs a quictls-patched openssl, big rebuild for
      #     marginal gain. Most distros still ship without HTTP/3.
      build = pkgs: pkgs.pkgsStatic.curl.override { http3Support = false; };

      # Windows build feature set (Schannel for TLS):
      #   - Schannel (Windows native TLS) instead of OpenSSL: zero CA
      #     bundle to ship, uses the Windows root certificate store.
      #   - HTTP/2 (nghttp2), zlib, brotli, zstd, libidn2, libpsl
      #   - libssh2 disabled: needs a crypto backend; without OpenSSL the
      #     options are wincng or mbedtls, both of which require
      #     overriding libssh2 itself. Microsoft's own curl.exe also
      #     ships without scp.
      windowsBuild = pkgs:
        let
          # mingwStaticCross applies makeStaticLibraries to the stdenv
          # under the isMinGW conditional, which adds
          # --enable-static/--disable-shared (autotools) and
          # -DBUILD_SHARED_LIBS=OFF (cmake) to every derivation. That
          # covers autotools libs like nghttp2 and libiconv without
          # per-package overrides.
          cross = ulib.mingwStaticCross pkgs;

          # zlib/zstd escape makeStaticLibraries (custom builder /
          # private cmake knobs); their static fix is in nix-lib's
          # `applyPackageFix`. brotli uses the generic
          # BUILD_SHARED_LIBS=OFF that the adapter already injects,
          # so no override there. The libidn2/libpsl/libunistring/
          # libiconv chain still needs surgery beyond --enable-static
          # (see comment per-lib).
          static = rec {
            zlib = ulib.applyPackageFix cross "zlib" cross.zlib;
            zstd = ulib.applyPackageFix cross "zstd" cross.zstd;

            # libunistring propagates libiconv on non-Linux. Without
            # pinning a libiconv whose `.a` lands first on -L, the
            # transitive ref pulls in a second SHARED libiconv via
            # .dll.a, and the linker resolves -liconv against it.
            libiconv = cross.libiconv;
            libunistring = cross.libunistring.override { inherit libiconv; };

            # libidn2 builds against the libunistring headers, which
            # are `__declspec(dllimport)`-decorated by default →
            # libidn2.a contains `__imp_*` refs that don't resolve
            # against the static libunistring.a unless libidn2 itself
            # was built against the same static libunistring.
            # Also drop libidn2's `bin` output: idn2.exe at runtime
            # pulls libiconv-2.dll, which transitively makes shared
            # libiconv appear on curl's -L path before our static one.
            libidn2 = (cross.libidn2.override {
              inherit libunistring;
            }).overrideAttrs (old: {
              outputs = builtins.filter (o: o != "bin") (old.outputs or []);
              postInstall = (old.postInstall or "") + ''
                rm -rf $out/bin || true
              '';
            });

            # libpsl: same dllimport hazard for its consumers; plus
            # we rewrite Libs:/Libs.private in libpsl.pc so curl's
            # PKG_CHECK_MODULES probe sees the transitive -l flags
            # in the right order.
            libpsl = libpslStaticFix libunistring libiconv
              (cross.libpsl.override { inherit libunistring libidn2; });
          };
        in
        ulib.mingwStandalone {
          pkg = cross.curl;
          staticDeps = {
            opensslSupport = false;
            scpSupport     = false;
            http3Support   = false;
            inherit (static) zlib zstd libidn2 libpsl;
          };
          # Drop --without-ssl that curl's package.nix injects when
          # opensslSupport=false. We're enabling Schannel below.
          filterConfigureFlag = f: f != "--without-ssl";
          extraConfigureFlags = [ "--with-schannel" ];
          extraOverrides = old: {
            # libidn2/libpsl declare libunistring/libiconv as plain
            # buildInputs (not propagated). With curl's strictDeps=true,
            # cc-wrapper only pulls -L paths from propagated inputs of
            # the immediate deps. Propagate them here so the link line
            # carries -L /.../libunistring/lib for the static .a.
            propagatedBuildInputs = (old.propagatedBuildInputs or [])
              ++ [ static.libunistring static.libiconv ];
            # The MinGW headers of nghttp2 (and a few others) declare
            # their public API as __declspec(dllimport) by default.
            # Linking the .a without the matching *_STATICLIB define
            # leaves __imp_* relocations the linker can't resolve.
            env = (old.env or {}) // {
              NIX_CFLAGS_COMPILE = builtins.concatStringsSep " " [
                "-DNGHTTP2_STATICLIB"
                "-DCURL_STATICLIB"
                "-DPSL_STATIC"
              ];
            };
          };
        };
    };
}

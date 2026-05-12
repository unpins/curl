{
  description = "Standalone build of curl";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    unpins-lib.url = "github:unpins/nix-lib/v1";
  };

  outputs = { self, nixpkgs, unpins-lib }:
    let
      lib = nixpkgs.lib;
      ulib = unpins-lib.lib;

      pkgsFor = system: import nixpkgs { inherit system; };

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

      # ---------------------------------------------------------------------
      # Builds
      # ---------------------------------------------------------------------

      # Native build feature set:
      #   openssl + zlib + nghttp2 (http2) + libssh2 (scp/sftp)
      #     — inherited from curlMinimal defaults
      #   + libidn2, libpsl, brotli, zstd
      #     — added by `pkgs.curl` over `curlMinimal`
      #   - http3 OFF: needs a quictls-patched openssl, big rebuild for
      #     marginal gain. Most distros still ship without HTTP/3.
      mkNative = system:
        let
          pkgs = pkgsFor system;
          curlNative = pkgs.pkgsStatic.curl.override { http3Support = false; };
        in
        ulib.packageWithMan pkgs "curl" curlNative;

      # Windows build feature set (Schannel for TLS):
      #   - Schannel (Windows native TLS) instead of OpenSSL: zero CA
      #     bundle to ship, uses the Windows root certificate store.
      #   - HTTP/2 (nghttp2), zlib, brotli, zstd, libidn2, libpsl
      #   - libssh2 disabled: needs a crypto backend; without OpenSSL the
      #     options are wincng or mbedtls, both of which require
      #     overriding libssh2 itself. Microsoft's own curl.exe also
      #     ships without scp.
      mkWindows = buildSystem:
        let
          pkgs = import nixpkgs {
            system = buildSystem;
            config.allowUnsupportedSystem = true;
          };
          cross = pkgs.pkgsCross.mingwW64;
          # Static-only versions of every lib that curl pulls. Crucially
          # these overrides are passed to `cross.curl.override` below —
          # they only substitute curl's inputs and do NOT propagate via
          # an `extend` overlay (which would touch the toolchain and
          # trigger a full xgcc rebuild because gcc uses zlib/zstd).
          # Each lib has its own static knob — nixpkgs doesn't standardize:
          #   brotli (cmake)  → staticOnly
          #   zlib   (custom) → shared = false
          #   zstd   (cmake)  → static = true
          # Autotools libs (libidn2, libunistring, libiconv, libpsl,
          # nghttp2) ride staticOnlyAuto which adds --disable-shared.
          static = rec {
            brotli       = cross.brotli.override { staticOnly = true; };
            zlib         = cross.zlib.override   { shared = false; };
            zstd         = cross.zstd.override   { static = true; };
            nghttp2      = ulib.staticOnlyAuto cross.nghttp2;
            libiconv     = ulib.staticOnlyAuto cross.libiconv;
            # libunistring propagates libiconv on non-Linux. If left as
            # the default (shared) cross.libiconv, that propagated
            # reference flows into curl's NIX_LDFLAGS *before* our static
            # libiconv path, and the linker resolves -liconv against the
            # .dll.a instead of the .a.
            libunistring = (ulib.staticOnlyAuto cross.libunistring).override {
              inherit libiconv;
            };
            # libidn2 must build against static libunistring (otherwise
            # libidn2.a contains __imp_* references to the SHARED
            # libunistring's symbols — its dllimport-decorated headers —
            # which won't resolve against plain libunistring.a).
            #
            # Also: drop the `bin` output. idn2.exe pulls libiconv-2.dll
            # at runtime, which transitively makes cross.libiconv (shared,
            # cached) appear in curl's -L path BEFORE our static libiconv,
            # and the linker then resolves -liconv against the .dll.a
            # rather than the .a. We don't ship idn2.exe anyway.
            libidn2 = ((ulib.staticOnlyAuto cross.libidn2).override {
              inherit libunistring;
            }).overrideAttrs (old: {
              outputs = builtins.filter (o: o != "bin") (old.outputs or []);
              # Block install of binaries; without `bin` output the
              # `moveToOutput` calls in libidn2's makefile would 404.
              postInstall = (old.postInstall or "") + ''
                rm -rf $out/bin || true
              '';
            });
            # libpsl: same dllimport hazard for the libs it consumes,
            # plus we promote Libs.private into Libs: so curl's
            # PKG_CHECK_MODULES probe sees the transitive -l flags.
            libpsl = libpslStaticFix libunistring libiconv
              ((ulib.staticOnlyAuto cross.libpsl).override {
                inherit libunistring libidn2;
              });
          };
          curlStandalone = ulib.mingwStandalone {
            pkg = cross.curl;
            staticDeps = {
              opensslSupport = false;
              scpSupport     = false;
              http3Support   = false;
              inherit (static) brotli zlib zstd nghttp2 libidn2 libpsl;
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
        in
        pkgs.symlinkJoin {
          name = "curl-${curlStandalone.version}";
          paths = [ curlStandalone.bin curlStandalone.man ];
          passthru = { inherit (curlStandalone) version pname; };
        };
    in
    {
      packages = lib.recursiveUpdate
        (ulib.forAllNative (system: { default = mkNative system; }))
        {
          # Windows cross via MinGW-w64. Produces a single PE/COFF .exe
          # importing only system DLLs (KERNEL32, MSVCRT, SCHANNEL, ...).
          # Built on x86_64-linux runners; the .exe runs on any Windows
          # x86_64 host without /nix/store or MSYS.
          x86_64-linux."windows-x86_64" = mkWindows "x86_64-linux";
        };

      apps = ulib.forAllNative (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/curl";
        };
      });
    };
}

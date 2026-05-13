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

      # Native feature set:
      #   openssl + zlib + nghttp2 + libssh2 + libidn2 + libpsl
      #   + brotli + zstd — taken from `pkgs.curl` defaults.
      #   http3 OFF: needs quictls-patched openssl.
      build = pkgs: pkgs.pkgsStatic.curl.override { http3Support = false; };

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
      };
    };
}

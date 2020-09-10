# This nix-shell script can be used to get a complete development environment
# for the Crystal compiler.
#
# You can choose which llvm version use and, on Linux, choose to use musl.
#
# $ nix-shell --pure
# $ nix-shell --pure --arg llvm 10
# $ nix-shell --pure --arg llvm 10 --arg musl true
# $ nix-shell --pure --arg llvm 9
# ...
# $ nix-shell --pure --arg llvm 6
#
# If needed, you can use https://app.cachix.org/cache/crystal-ci to avoid building
# packages that are not available in Nix directly. This is only useful for musl so far.
#
# $ nix-env -iA cachix -f https://cachix.org/api/v1/install
# $ cachix use crystal-ci
# $ nix-shell --pure --arg musl true
#

{llvm ? 10, musl ? false}:

let
  nixpkgs = import (builtins.fetchTarball {
    name = "nixpkgs-20.03";
    url = "https://github.com/NixOS/nixpkgs/archive/2d580cd2793a7b5f4b8b6b88fb2ccec700ee1ae6.tar.gz";
    sha256 = "1nbanzrir1y0yi2mv70h60sars9scwmm0hsxnify2ldpczir9n37";
  }) {};

  pkgs = if musl then nixpkgs.pkgsMusl else nixpkgs;

  genericBinary = { url, sha256 }:
    pkgs.stdenv.mkDerivation rec {
      name = "crystal-binary";
      src = builtins.fetchTarball { inherit url sha256; };

      # Extract only the compiler binary
      buildCommand = ''
        mkdir -p $out/bin

        # Darwin packages use embedded/bin/crystal
        [ -f "${src}/embedded/bin/crystal" ] && cp ${src}/embedded/bin/crystal $out/bin/

        # Linux packages use lib/crystal/bin/crystal
        [ -f "${src}/lib/crystal/bin/crystal" ] && cp ${src}/lib/crystal/bin/crystal $out/bin/
      '';
    };

  # Hashes obtained using `nix-prefetch-url --unpack <url>`
  latestCrystalBinary = genericBinary ({
    x86_64-darwin = {
      url = "https://github.com/crystal-lang/crystal/releases/download/0.35.1/crystal-0.35.1-1-darwin-x86_64.tar.gz";
      sha256 = "sha256:0gpn42xh372hw2bqfgxc9wibpbam8gn7gx3p1b8p9adydjg0zxfm";
    };

    x86_64-linux = {
      url = "https://github.com/crystal-lang/crystal/releases/download/0.35.1/crystal-0.35.1-1-linux-x86_64.tar.gz";
      sha256 = "sha256:077pby4ylf0z831gg0hbiwxcq3g0yl0cdlybirgg8rv24a2sa7zh";
    };

    i686-linux = {
      url = "https://github.com/crystal-lang/crystal/releases/download/0.35.1/crystal-0.35.1-1-linux-i686.tar.gz";
      sha256 = "sha256:0nfgxjndfslyacicjy4303pvvqfg74v5fnpr4b10ss9rqakmlbgd";
    };
  }.${pkgs.stdenv.system});

  pkgconfig = pkgs.pkgconfig;

  llvm_suite = ({
    llvm_10 = {
      llvm = pkgs.llvm_10;
      extra = [ pkgs.lld_10 pkgs.lldb_10 ];
    };
    llvm_9 = {
      llvm = pkgs.llvm_9;
      extra = [ ]; # lldb it fails to compile on Darwin
    };
    llvm_8 = {
      llvm = pkgs.llvm_8;
      extra = [ ]; # lldb it fails to compile on Darwin
    };
    llvm_7 = {
      llvm = pkgs.llvm;
      extra = [ pkgs.lldb ];
    };
    llvm_6 = {
      llvm = pkgs.llvm_6;
      extra = [ ]; # lldb it fails to compile on Darwin
    };
  }."llvm_${toString llvm}");

  boehmgc = pkgs.boehmgc.overrideAttrs (oldAttrs: rec {
    patches = [
      (pkgs.fetchpatch {
        url = "https://raw.githubusercontent.com/crystal-lang/distribution-scripts/e942880dda3b100ff1143cce88b579bbec3f05b9/linux/files/feature-thread-stackbottom-upstream.patch";
        sha256 = "784ade9fe1c2668db77a3c08cd195cd7701331bdf8c9d160038cfce099b77e37";
      })
    ];
  });

  stdLibDeps = with pkgs; [
      gmp libevent libiconv libxml2 libyaml openssl pcre zlib
    ] ++ stdenv.lib.optionals stdenv.isDarwin [ libiconv ];

  tools = [ pkgs.hostname llvm_suite.extra ];
in

pkgs.stdenv.mkDerivation rec {
  name = "crystal-dev";

  buildInputs = tools ++ stdLibDeps ++ [
    latestCrystalBinary
    pkgconfig
    llvm_suite.llvm
    boehmgc
  ];

  LLVM_CONFIG = "${llvm_suite.llvm}/bin/llvm-config";

  # ld: warning: object file (.../src/ext/libcrystal.a(sigfault.o)) was built for newer OSX version (10.14) than being linked (10.12)
  MACOSX_DEPLOYMENT_TARGET = "10.11";
}

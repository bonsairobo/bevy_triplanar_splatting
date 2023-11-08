{
  description = "NixOS environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    devShell.${system} = with pkgs;
      mkShell rec {
        ###
        ## Library Packages
        ###

        xLibs = with pkgs; [
          xorg.libX11
          xorg.libXcursor
          xorg.libXi
          xorg.libXrandr
        ];
        dynLibs = with pkgs;
          [
            alsa-lib
            stdenv.cc.cc.lib
            udev
            vulkan-loader
          ]
          ++ xLibs;

        ###
        ## Executable Packages
        ###

        buildInputs = with pkgs;
          [
            clang
            # Replace llvmPackages with llvmPackages_X, where X is the latest
            # LLVM version (at the time of writing, 16)
            llvmPackages_16.bintools
            mold
            pkg-config
            rustup
          ]
          ++ dynLibs;

        ###
        ## Rust Toolchain Setup
        ###

        RUSTC_VERSION = pkgs.lib.readFile ./rust-toolchain;
        shellHook = ''
          export PATH=$PATH:''${CARGO_HOME:-~/.cargo}/bin
          export PATH=$PATH:''${RUSTUP_HOME:-~/.rustup}/toolchains/$RUSTC_VERSION-x86_64-unknown-linux-gnu/bin/
        '';

        ###
        ## Rust Bindgen Setup
        ###

        # So bindgen can find libclang.so
        LIBCLANG_PATH = pkgs.lib.makeLibraryPath [pkgs.llvmPackages_16.libclang.lib];
        # Add headers to bindgen search path
        BINDGEN_EXTRA_CLANG_ARGS =
          # Includes with normal include path
          (builtins.map (a: ''-I"${a}/include"'') [
            # add dev libraries here (e.g. pkgs.libvmi.dev)
            pkgs.glibc.dev
          ])
          # Includes with special directory paths
          ++ [
            ''-I"${pkgs.llvmPackages_16.libclang.lib}/lib/clang/${pkgs.llvmPackages_16.libclang.version}/include"''
            ''-I"${pkgs.glib.dev}/include/glib-2.0"''
            ''-I${pkgs.glib.out}/lib/glib-2.0/include/''
          ];

        ###
        ## Linking with System libraries
        ###

        # Add precompiled library to rustc search path
        RUSTFLAGS = builtins.map (a: ''-L ${a}/lib'') dynLibs;

        # For some reason the Vulkan loader needs to be in the dynamic linker path.
        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [pkgs.vulkan-loader];
      };
  };
}

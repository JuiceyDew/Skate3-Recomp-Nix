{
  description = "Build environment for skate3recomp (Skate 3 native recompilation) on NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # ReXGlue requires Clang 20. Build the shell with that stdenv so
        # CC/CXX default to clang-20 and lld-20 is the linker.
        llvm = pkgs.llvmPackages_20;

        # Everything the upstream README installs via apt, mapped to nixpkgs.
        runtimeLibs = with pkgs; [
          # Graphics / windowing
          gtk3
          xorg.libX11        # provides libX11-xcb (pkg-config: x11-xcb)
          xorg.libxcb
          vulkan-headers
          vulkan-loader
          vulkan-tools       # vulkaninfo / vkcube for sanity checks
          mesa               # vulkan drivers (system ICD used at runtime)
          vulkan-validation-layers

          # Audio
          alsa-lib           # libasound2-dev
          libpulseaudio      # libpulse-dev
          pipewire           # libpipewire-0.3-dev

          # Input / device
          udev               # libudev-dev

          # Optional deps from the README
          libusb1            # libusb-1.0-0-dev
          libunwind          # libunwind-dev
          ibus               # libibus-1.0-dev
          liburing           # liburing-dev
        ];
      in {
        devShells.default = pkgs.mkShell.override { stdenv = llvm.stdenv; } {
          nativeBuildInputs = with pkgs; [
            cmake
            ninja
            pkg-config
            git
            p7zip            # p7zip-full (extracting the game dump)
            python3          # build scripts
            llvm.clang       # clang-20
            llvm.lld         # lld-20
          ];

          buildInputs = runtimeLibs;

          shellHook = ''
            export CC=clang
            export CXX=clang++

            # The CMake presets hardcode version-suffixed tool names
            # (clang-20 / clang++-20 / ld.lld-20), but nixpkgs ships them
            # unsuffixed. Create shims pointing at the *wrapped* Nix tools so
            # the presets work unmodified.
            SHIM_DIR="$PWD/.nix-toolchain-shims"
            mkdir -p "$SHIM_DIR"
            ln -sf "$(command -v clang)"   "$SHIM_DIR/clang-20"
            ln -sf "$(command -v clang++)" "$SHIM_DIR/clang++-20"
            ln -sf "${llvm.lld}/bin/ld.lld" "$SHIM_DIR/ld.lld-20"
            export PATH="$SHIM_DIR:$PATH"

            # Let the Vulkan loader find the system (NixOS) GPU driver ICD at runtime.
            export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/intel_icd.x86_64.json:/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json:/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath runtimeLibs}:/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            echo "skate3recomp dev shell — clang-20: $(clang-20 --version | head -1)"
          '';
        };
      });
}

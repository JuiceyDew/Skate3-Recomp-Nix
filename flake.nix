{
  description = "Run the prebuilt Skate 3 recompilation (upstream Linux release) on NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  # The upstream Linux release is an x86_64 binary, so this flake only targets
  # x86_64-linux. (macOS/Windows have their own upstream releases.)
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = pkgs.lib;

        # ReXGlue requires Clang 20 for the (optional) from-source build.
        llvm = pkgs.llvmPackages_20;

        # ----------------------------------------------------------------------
        # Primary path: the upstream PREBUILT Linux release.
        #
        # This is the same `skate3` binary mchughalex ships on the releases
        # page — the one whose first-run "Select ISO" popup imports your game.
        # On NixOS it can't start as-is: its ELF interpreter is
        # /lib64/ld-linux-x86-64.so.2 (absent on NixOS) and it links the GTK
        # stack with only an $ORIGIN rpath. We patch the interpreter, put the
        # GTK libraries on its rpath, and wire up the runtime env so the popup,
        # Vulkan rendering, and controller input all work. We change nothing
        # about the binary's behavior — we only re-home it onto Nix libraries.
        # ----------------------------------------------------------------------
        releaseVersion = "1.0.4";
        releaseSrc = pkgs.fetchurl {
          url =
            "https://github.com/mchughalex/skate3recomp/releases/download/v${releaseVersion}/Skate3Recomp-Linux.zip";
          hash = "sha256-+4eERneK934V8S3oF1/CJliOmFB8pwBekixCrQuhhy4=";
        };

        # Libraries the binary links against (DT_NEEDED) plus the GTK runtime
        # bits the file-chooser popup needs to render and pick a file.
        appLibs = with pkgs; [
          gtk3
          glib
          pango
          cairo
          harfbuzz
          atk
          gdk-pixbuf
          zlib
          stdenv.cc.cc.lib # libstdc++ / libgcc_s
          libx11 # also provides libX11-xcb
          libxcb

          # Make the GTK dialog actually usable (schemas, icons, mime, svg).
          gsettings-desktop-schemas
          librsvg
          shared-mime-info
          adwaita-icon-theme
          hicolor-icon-theme
        ];

        # Libraries the binary dlopen()s at runtime (so they are NOT in NEEDED
        # and autoPatchelf can't see them): the Vulkan loader and the SDL
        # controller backend. The actual GPU driver/ICD is provided by the host
        # at /run/opengl-driver (NixOS `hardware.graphics.enable = true;`).
        dlopenLibs = with pkgs; [ vulkan-loader SDL2 libGL ];

        skate3App = pkgs.stdenv.mkDerivation {
          pname = "skate3";
          version = releaseVersion;
          src = releaseSrc;
          sourceRoot = "Skate3Recomp-Linux";

          nativeBuildInputs = with pkgs; [ unzip autoPatchelfHook wrapGAppsHook3 ];
          buildInputs = appLibs ++ dlopenLibs;

          dontBuild = true;
          dontConfigure = true;

          # librexruntime.so references the Steamworks SDK for optional Steam
          # Input support. libsteam_api.so is only present when launched through
          # Steam; it isn't a standalone Nix package and the game runs fine
          # without it, so leave the (lazily-bound) reference unsatisfied.
          autoPatchelfIgnoreMissingDeps = [ "libsteam_api.so" ];

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            # Keep skate3 and librexruntime.so together so the binary's
            # $ORIGIN rpath continues to resolve the runtime library.
            cp skate3 librexruntime.so $out/bin/
            chmod 0755 $out/bin/skate3
            # The release ships the .so with the executable bit set; clear it so
            # wrapGAppsHook doesn't mistake the library for a program and wrap
            # it (which would shadow the real lib with a tiny wrapper stub).
            chmod 0644 $out/bin/librexruntime.so
            runHook postInstall
          '';

          # The Vulkan/SDL libs are dlopen()d, so add them (and the system GPU
          # driver path) to the env of the wrapper wrapGAppsHook generates.
          preFixup = ''
            gappsWrapperArgs+=(
              --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath dlopenLibs}:/run/opengl-driver/lib"
            )
          '';

          meta = {
            description =
              "Prebuilt Skate 3 recompilation (upstream Linux release), wrapped to run on NixOS";
            homepage = "https://github.com/JuiceyDew/Skate3-Recomp-Nix";
            platforms = [ "x86_64-linux" ];
            sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
          };
        };

        # User-facing launcher: choose a writable game-data directory, then run
        # the wrapped binary. On first run the binary shows the "Select ISO"
        # popup and extracts your own legally-dumped Skate 3 ISO into that dir;
        # subsequent runs find the installed game there and boot straight in.
        launcher = pkgs.writeShellApplication {
          name = "skate3";
          runtimeInputs = [ pkgs.coreutils ];
          text = ''
            game="''${SKATE3_GAME_DATA_ROOT:-''${XDG_DATA_HOME:-$HOME/.local/share}/skate3/game}"
            mkdir -p "$game"
            echo "skate3: using game data directory: $game" >&2
            echo "skate3: (override with SKATE3_GAME_DATA_ROOT=/path)" >&2
            exec ${skate3App}/bin/skate3 --game_data_root="$game" --input_backend=sdl "$@"
          '';
        };

        # ----------------------------------------------------------------------
        # Optional path: build from source. Kept for contributors who want to
        # recompile the binary themselves; see the README's "Build from source"
        # appendix. Not needed just to play.
        # ----------------------------------------------------------------------
        sourceBuildLibs = with pkgs; [
          gtk3
          libx11
          libxcb
          vulkan-headers
          vulkan-loader
          vulkan-tools
          mesa
          vulkan-validation-layers
          alsa-lib
          libpulseaudio
          pipewire
          udev
          libusb1
          libunwind
          ibus
          liburing
        ];
      in {
        packages.skate3 = launcher;
        packages.skate3-unwrapped = skate3App;
        packages.default = launcher;

        apps.skate3 = {
          type = "app";
          program = "${launcher}/bin/skate3";
        };
        apps.default = self.apps.${system}.skate3;

        devShells.default = pkgs.mkShell.override { stdenv = llvm.stdenv; } {
          nativeBuildInputs = with pkgs; [
            cmake
            ninja
            pkg-config
            git
            p7zip
            python3
            llvm.clang
            llvm.lld
          ];

          buildInputs = sourceBuildLibs;

          shellHook = ''
            export CC=clang
            export CXX=clang++

            # The CMake presets hardcode version-suffixed tool names
            # (clang-20 / clang++-20 / ld.lld-20); nixpkgs ships them
            # unsuffixed. Shim them so the upstream presets run unmodified.
            SHIM_DIR="$PWD/.nix-toolchain-shims"
            mkdir -p "$SHIM_DIR"
            ln -sf "$(command -v clang)"   "$SHIM_DIR/clang-20"
            ln -sf "$(command -v clang++)" "$SHIM_DIR/clang++-20"
            ln -sf "${llvm.lld}/bin/ld.lld" "$SHIM_DIR/ld.lld-20"
            export PATH="$SHIM_DIR:$PATH"

            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath sourceBuildLibs}:/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            echo "skate3recomp source-build shell — clang-20: $(clang-20 --version | head -1)"
          '';
        };
      });
}

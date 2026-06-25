<picture>
  <source media="(prefers-color-scheme: dark)" srcset="banner.png">
  <source media="(prefers-color-scheme: light)" srcset="banner-light.png">
  <img alt="Skate 3 Native PC Recompilation" src="banner-light.png">
</picture>

A **Nix / NixOS** fork of [skate3recomp](https://github.com/mchughalex/skate3recomp), the unofficial
native recompilation of the Xbox 360 version of Skate 3. This fork makes the **upstream prebuilt
Linux release run on NixOS** with a single `nix run`. It wraps the official `Skate3Recomp-Linux.zip`
binary so its first-run **“Select ISO”** popup — the one that imports your game — works on a system
that has no `/usr/lib` and no system dynamic linker.

The game is capable of running at ~165FPS at 4K with MSAA on an RTX 4090.

The project does not include Skate 3 retail game files. The first time you launch it, the binary opens
a file picker so you can select your own legally obtained Xbox 360 Skate 3 **ISO**, which it then
extracts and installs.

> **Why this fork?** The upstream Linux binary expects `/lib64/ld-linux-x86-64.so.2` and a system GTK
> stack, neither of which exists on NixOS, so it can't even start there — which means its ISO-import
> popup never appears. This flake fetches the official release, patches its interpreter, puts GTK,
> Vulkan and SDL on its library path, and wires up the GTK runtime so the popup, rendering and
> controller input all work. The binary itself is unmodified.

## How Do I Play?

You need:

- **NixOS** (or any Linux with the Nix package manager) with
  [flakes enabled](https://nixos.wiki/wiki/Flakes) (`experimental-features = nix-command flakes`).
- A working GPU driver exposed at `/run/opengl-driver` — on NixOS set
  `hardware.graphics.enable = true;` (the default on most desktop setups).
- Your own legally obtained Skate 3 Xbox 360 **ISO**.

Then just run:

```sh
nix run github:JuiceyDew/Skate3-Recomp-Nix
```

On first launch the **“Select Skate 3 Xbox 360 ISO”** popup appears. Pick your ISO; it’s extracted and
installed, and the game boots. Later launches find the installed game and start straight away.

By default the game is installed under `~/.local/share/skate3/game` (i.e.
`$XDG_DATA_HOME/skate3/game`). To use a different location — or point at an already-extracted dump —
set `SKATE3_GAME_DATA_ROOT`:

```sh
SKATE3_GAME_DATA_ROOT=/games/skate3 nix run github:JuiceyDew/Skate3-Recomp-Nix
```

Pass game arguments after `--`, e.g. start windowed:

```sh
nix run github:JuiceyDew/Skate3-Recomp-Nix -- --no-fullscreen
```

Fullscreen is on by default. Controller input uses the SDL backend.

## Install It Into Your Config

Add this repo as an input to your system or Home Manager flake:

```nix
# flake.nix
{
  inputs.skate3.url = "github:JuiceyDew/Skate3-Recomp-Nix";
  # ...
}
```

Then add the launcher to your packages. In Home Manager:

```nix
# home.nix  (module args include `inputs` and `pkgs`)
home.packages = [ inputs.skate3.packages.${pkgs.system}.default ];
```

or system-wide in `configuration.nix`:

```nix
environment.systemPackages = [ inputs.skate3.packages.${pkgs.system}.default ];
```

This puts a `skate3` command on your `PATH`. Run `skate3` from anywhere; it manages the install
directory and ISO import for you.

> **Vulkan note.** The wrapped binary relies on your *system* GPU driver exposed at
> `/run/opengl-driver`, which requires `hardware.graphics.enable = true;` in your NixOS config (the
> default on desktop setups). Check your ICD is visible with `ls /run/opengl-driver/share/vulkan/icd.d/`.

## Flake Outputs

| Output | What it is |
| --- | --- |
| `packages.default` / `packages.skate3` | Launcher that picks a writable game dir and runs the wrapped binary. |
| `packages.skate3-unwrapped` | The patched upstream binary + `librexruntime.so`, without the launcher logic. |
| `apps.default` / `apps.skate3` | `nix run` target for the launcher. |
| `devShells.default` | Clang 20 / CMake / Vulkan toolchain for building from source (see below). |

The launcher reads:

- `SKATE3_GAME_DATA_ROOT` — where the game is installed / extracted (default
  `~/.local/share/skate3/game`).
- `XDG_STATE_HOME` — base for the writable log directory
  (`$XDG_STATE_HOME/skate3/logs`, default `~/.local/state/skate3/logs`). The
  upstream binary defaults to a `logs` folder beside the executable, which on
  NixOS is the read-only store; the launcher redirects logging here so startup
  doesn't abort.

## Installing DLC

To use DLC, provide package files from your own legally obtained Xbox 360 DLC. Create a `dlc` folder
beside the executable, inside the installed game folder, or in the user data folder, drop the DLC
package files in it, and start the game.

## True 21:9 Ultrawide

The build includes an experimental true ultrawide aspect ratio mode at 21:9. You may notice occasional
visual bugs, especially around shadows, and performance is somewhat reduced.

## Controls

- Standard Xbox controls using an Xbox controller are the preferred and main input method. DualShock
  and others are untested, but are likely to work with Steam Input through XInput.
- Keyboard controls can be enabled in the game settings menu.
- Press Escape on keyboard or (Back + Start) on the controller to open the game settings menu.

### Keyboard Keybinds

- Left stick: W/A/S/D
- Right stick: mouse movement
- A/B/X/Y: Space/C/E/F
- LT/RT: RMB/LMB
- LB/RB: Q/R
- Left stick press: Shift
- Right stick press: MMB
- Back/Start: Tab/Return

## Build From Source (optional)

You only need this if you want to recompile the binary yourself instead of using the upstream release.
Skate 3 here is a *static recompilation*: the `skate3` binary is generated from your own
legally-dumped game files at build time, so there is nothing prebuilt to cache for this path.

Clone with submodules and enter the dev shell (Clang 20, CMake, Ninja, Vulkan, GTK 3, audio/input
libs, plus `clang-20` / `clang++-20` / `ld.lld-20` shims so the upstream presets run unmodified):

```sh
git clone --recursive git@github.com:JuiceyDew/Skate3-Recomp-Nix.git skate3recomp
cd skate3recomp
nix develop
```

The build-time codegen needs an extracted dump containing `default.xex` and
`data/webkit/EAWebkit.xex`:

```sh
mkdir -p game
cp /path/to/default.xex /path/to/EAWebkit.xex game/
```

Generate the recompiled source, reconfigure so CMake sees the generated source lists, then build
(inside the `nix develop` shell):

```sh
cmake --preset linux-relwithdebinfo -DSKATE3_GAME_DATA_ROOT="$PWD/game"
cmake --build --preset linux-relwithdebinfo --target generate-all --parallel
cmake --preset linux-relwithdebinfo -DSKATE3_GAME_DATA_ROOT="$PWD/game"
cmake --build --preset linux-relwithdebinfo --parallel
```

Run the locally-built binary (note this is the *runtime* game data, which the ISO popup also
populates):

```sh
LD_LIBRARY_PATH="$PWD/third_party/rexglue-sdk/out/linux-amd64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  ./out/build/linux-relwithdebinfo/skate3 --game_data_root="$PWD/game" --input_backend=sdl
```

`third_party/rexglue-sdk` is pinned as a Git submodule on the `skate3-sdk-clean` branch of the
Skate-specific rexglue fork (based on rexglue 0.8.0). If you cloned without submodules:

```sh
git submodule sync --recursive
git submodule update --init --recursive --jobs "$(nproc 2>/dev/null || echo 4)"
```

## Credits

- [skate3recomp](https://github.com/mchughalex/skate3recomp) by mchughalex — the upstream project this
  is forked from, and the source of the prebuilt release this flake wraps.
- [rexglue SDK](https://github.com/rexglue/rexglue-sdk), the recompilation SDK used by this project.
- [Xenia](https://github.com/xenia-project/xenia), whose Xbox 360 research and tooling have helped the
  broader recompilation ecosystem.

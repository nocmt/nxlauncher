# NxLauncher

A macOS app for the [nxnative](https://github.com/seedds/nxnative) pipeline: point it at a game's
NSP/XCI, and it builds the IPA, runs the game, and exports what you want to hand to someone.

![the window](docs/screenshot.png)

## What it does

| | |
|---|---|
| **Game library** | Remembers multiple game folders with artwork, version and build status. Select a tile to inspect it or open its workspace. Removing a record leaves the original files, build output and saves intact. |
| **Game data** | The folder with the base game (NSP **or** XCI), the update and the DLC. The app sorts them out, reads the icon and the name out of the game, and says whether the game has a port (a profile in `dm/games/`). |
| **Several files** | A folder can hold more than one update and more than one DLC. The row shows how many, and opening it lists them one by one -- the title ID first, because it always fits, and then the name without it. Hover a line for the full path. |
| **Host keys** | A shared `prod.keys` path in the library's General Settings, remembered between launches. The key file stays in its original location. No firmware: the pipeline does not use one. |
| **Settings** | General Settings holds appearance, host keys and build environment diagnostics. Each game's workspace holds its frame rate, language and operation mode (handheld 720p / console 1080p), saved to its own `env.txt`. |
| **Build log** | Read-only native text with multiline selection, standard Copy/Select All shortcuts and a Copy All button. |
| **Start** | Compiles the game the first time (30–60 minutes, the shaders), then starts it. |
| **Export** | The Mac `.app` and the iOS IPA. Each export asks where to put it: the export is written from the work folder, so it is a new copy every time. |

## Install

```bash
git clone <this repository> nxlauncher
cd nxlauncher
./bootstrap.sh          # the nxnative submodule + our patches + the toolchain check
```

`bootstrap.sh` prepares the submodule and patches, creates a repository-local Python virtual
environment, installs its Python packages and builds the launcher. It does **not** install system
tools: it reports missing Xcode components, `xcodegen`, `zstd`, `spirv-cross` and the arm64 .NET 10
SDK/runtime. `./bootstrap.sh --check` is read-only.

The app checks its build environment on launch and again before a build. The **编译环境** section
shows missing dependencies and installation guidance; it never runs installers or changes system
configuration. Full builds need Xcode with the iPhoneOS SDK and Metal tools, Make/Clang, `xcodegen`,
`zstd`, `spirv-cross`, .NET 10, and Python 3.12+ with `lz4`, `capstone`, `fonttools`, `Pillow` and
zstd support (`backports.zstd` before Python 3.14). Homebrew is optional if the tools are installed
another way. This pipeline does not require separate `cmake`, `ninja`, `opus` or `libvpx` packages:
libvpx is built from upstream's bundled source and Opus uses the game SDK decoder.

The launcher supplies a GUI-safe PATH and discovers the .NET runtime root, including Homebrew's
`libexec` layout. It passes `DOTNET_ROOT_ARM64` / `DOTNET_ROOT` to all build subprocesses, including
`nx_extract`, so launching from Finder does not depend on shell startup files. Valid explicit .NET
root overrides are preserved; diagnostics verify the selected arm64 SDK/runtime is compatible with
.NET 10 rather than merely checking whether a `dotnet` command exists.

## Run

```bash
swift run NxLauncher                      # the app
swift run NxLauncher --game-dir ~/Games/BotW --keys ~/keys/prod.keys
bash Scripts/make-app.sh                  # a double-clickable NxLauncher.app in dist/
```

## The app carries its own tools

`Scripts/make-app.sh` puts everything the app needs into the bundle, in **one archive**
(`Contents/Resources/nxlauncher-home.tgz`, about 50 MB): the pipeline, the upstream source tree, a
standalone Python 3.13 and the wheels for `lz4` / `capstone` / `fontTools` / `Pillow` / `backports.zstd`.

So the `.app` can be handed to someone as a single file: it needs no repository, no Python and no
`pip` on that machine. On the first run it unpacks the archive into
`~/Library/Caches/NxLauncher/home` (not into the bundle: the bundle can be read-only, and the build
writes into the tree) and installs the Python's packages from the wheels, offline.

What the app still needs from the machine it runs on:

| | |
|---|---|
| **Playing** | nothing -- the exported `.app` is all a player needs |
| **Exporting a Mac .app** | Xcode's command line tools (the host is compiled) |
| **Building the IPA** | the whole toolchain: Xcode, `xcodegen`, `.NET SDK 10`, `spirv-cross`, `zstd` |
| **The game** | the NSP/XCI, the DLC and the keys -- the files themselves, of course |

The archive is rebuilt by `Scripts/make-home-archive.sh` (it needs a standalone Python 3.13; `uv`
keeps one in its cache).

## The pipeline from the command line

The app is a thin layer over `Tools/pack_pipeline.py`, which speaks the same JSON event stream the
upstream packing script emits with `--progress json` (one JSON object per line). So everything the
app does can be done from a terminal, and something else could drive it too:

```bash
python3 Tools/pack_pipeline.py plan   --game-dir ~/Games/BotW --keys ~/keys/prod.keys
python3 Tools/pack_pipeline.py doctor                      # read-only build environment report
python3 Tools/pack_pipeline.py games                       # the games that have a port
python3 Tools/pack_pipeline.py build  --game-dir ~/Games/BotW --keys ~/keys/prod.keys
python3 Tools/pack_pipeline.py export --target mac-app --game 01007EF00011E000 --ver v1114112 \
                                     --work ~/Games/BotW/01007EF00011E000_build --out ~/Desktop/BotW.app
python3 Tools/pack_pipeline.py export --target ios-ipa-unsigned --work <build dir> --out <the ipa>
```

## How it is put together

```
NxLauncher/
├── Sources/NxLauncher/        the SwiftUI app (the window, the state, the process plumbing)
├── Tools/
│   ├── pack_pipeline.py       the orchestrator: plan / build / export, one JSON event stream
│   ├── make-mac-app.sh        the Mac .app (any game with a profile)
│   ├── make-signed-ipa.sh     the signed iOS IPA
│   ├── make-unsigned-ipa.sh   the unsigned iOS IPA (for a colleague to re-sign)
│   ├── launcher.c             the Mac .app's launcher (sets the environment, execs the host)
│   ├── make-icns.py           the game's own icon.jpg -> .icns
│   └── make-info-plist.py     the .app's Info.plist, from the profile
├── patches/                   our changes to the upstream tree (see below)
├── nxnative/                  the upstream tree, a submodule
├── bootstrap.sh               the submodule + the patches + the toolchain check
├── Resources/
│   ├── AppIcon.icns           the launcher's icon (the Switch logo)
│   └── wheels/                the Python packages, for the offline install in the app
└── Scripts/
    ├── make-app.sh            the launcher as a macOS .app
    └── make-home-archive.sh   the archive the app carries (the tools + the tree + the Python)
```

### The patches

The upstream tree is a submodule pinned to **`677345b0933f5f8754aeec3125d14df32683ca97`**
(the upstream `main` fetched on 2026-10-22), not to an unpublished local commit. Our nine patches are
maintained independently as an ordered patch series in `patches/series`; `patches/base-commit`
records the exact upstream baseline. See [the patch inventory and upstream PRs](patches/README.md).

```bash
python3 Tools/prepare-nxnative.py          # apply the complete series to the pinned dependency
python3 Tools/prepare-nxnative.py --check  # verify the complete resulting tree without changing it
python3 -m unittest discover -s Tests -v # preparation safety and repeatability tests
```

Preparation keeps the submodule's HEAD at the upstream commit and leaves the patches as local
working-tree changes. It refuses an unexpected baseline, staged edits, partially applied patches,
and changes that do not match the complete series. `bootstrap.sh` prepares the dependency;
`Scripts/make-home-archive.sh` verifies it before packaging, so a release cannot silently omit patches.

The old `bc5815a` patch is retained under `patches/archive/` for reference only. Upstream's Mac
controller bridge, fullscreen support and display pacing are used rather than replaced. The mouse
routing and JSON progress contributions from [PR #48](https://github.com/seedds/nxnative/pull/48) and
[PR #49](https://github.com/seedds/nxnative/pull/49) were adapted upstream in `b302d40` and `f1c4a6b`,
with additional fixes by the maintainer; their local patches have been retired. When upstream adopts
a patch, update the baseline, remove that patch from the series, and verify again.

### What is not automated

The pipeline is general: it takes any NSP/XCI + DLC + keys. What is **not** general is the port:
a game needs a profile in `dm/games/` (its title ID, its modules, its memory split, its shader
tables). The upstream script can write a survey and guess a provisional profile for a game that has
none, and packs a best-effort IPA that **may not boot**. The available profiles are listed by
`python3 Tools/pack_pipeline.py games`; this launcher automates those, not the porting.

## License

MIT (see LICENSE). The upstream tree keeps its own license. The game files belong to their owner:
this repository ships **no** game data and no keys.

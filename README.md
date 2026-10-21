# NxLauncher

A macOS app for the [nxnative](https://github.com/seedds/nxnative) pipeline: point it at a game's
NSP/XCI, and it builds the IPA, runs the game, and exports what you want to hand to someone.

![the window](docs/screenshot.png)

## What it does

| | |
|---|---|
| **Game data** | The folder with the base game (NSP **or** XCI), the update and the DLC. The app sorts them out, reads the icon and the name out of the game, and says whether the game has a port (a profile in `dm/games/`). |
| **Several files** | A folder can hold more than one update and more than one DLC. The row shows how many, and opening it lists them one by one -- the title ID first, because it always fits, and then the name without it. Hover a line for the full path. |
| **Host keys** | `prod.keys`. No firmware: the pipeline does not use one. |
| **Settings** | Target frame rate (60 / 30), language (follow the system / 简体中文 / English), the export folder. They are written to the game's `env.txt`, so they take effect on the next start. |
| **Start** | Compiles the game the first time (30–60 minutes, the shaders), then starts it. |
| **Export** | The Mac `.app` and the iOS IPA, into the folder you chose. |

## Install

```bash
git clone <this repository> nxlauncher
cd nxlauncher
./bootstrap.sh          # the nxnative submodule + our patches + the toolchain check
```

`bootstrap.sh` needs a Mac with Xcode and Homebrew. It installs nothing by itself: it tells you what
is missing (`xcodegen`, `zstd`, `spirv-cross`, `dotnet-sdk`, and `lz4` / `capstone` / `fonttools` /
`Pillow` for Python).

## Run

```bash
swift run NxLauncher                      # the app
swift run NxLauncher --game-dir ~/Games/BotW --keys ~/keys/prod.keys
bash Scripts/make-app.sh                  # a double-clickable NxLauncher.app in dist/
```

## The pipeline from the command line

The app is a thin layer over `Tools/pack_pipeline.py`, which speaks the same JSON event stream the
upstream packing script emits with `--progress json` (one JSON object per line). So everything the
app does can be done from a terminal, and something else could drive it too:

```bash
python3 Tools/pack_pipeline.py plan   --game-dir ~/Games/BotW --keys ~/keys/prod.keys
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
├── Resources/AppIcon.icns     the launcher's icon (drawn by Scripts/make-icon.swift)
└── Scripts/
    ├── make-app.sh            the launcher as a macOS .app
    └── make-icon.sh           draws the icon again (the .icns is kept in the repository)
```

### The patches

The upstream tree is a submodule pinned to **`bc5815a`** -- the commit our patch was made against.
The patch carries the changes the launcher needs from the upstream tree:

- the Mac host: the frame rate counter, the mouse look, the window size, the system language, the
  memory switches, the physical controller bridge (Switch / PS5 / Xbox);
- the iOS app: the same controller mapping, by vendor;
- the packing script: **`--progress json`**, the machine-readable progress the GUI reads.

Upstream moves on, and the patch does not apply to newer commits (upstream has since restructured
those files). Bumping the submodule means rebasing the patch and re-verifying the build.

### What is not automated

The pipeline is general: it takes any NSP/XCI + DLC + keys. What is **not** general is the port:
a game needs a profile in `dm/games/` (its title ID, its modules, its memory split, its shader
tables). The upstream script can write a survey and guess a provisional profile for a game that has
none, and packs a best-effort IPA that **may not boot**. Upstream has 16 games with a profile;
this launcher automates those, not the porting.

## License

MIT (see LICENSE). The upstream tree keeps its own license. The game files belong to their owner:
this repository ships **no** game data and no keys.

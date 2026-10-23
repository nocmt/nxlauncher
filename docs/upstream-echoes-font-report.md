# Draft upstream report: shared-font presentation in Echoes of Wisdom

**Draft only — not published.**

Suggested title: **Echoes of Wisdom 1.1.0: shared fonts skip Decode despite its import; `shared_font ttf` fixes font-load crash**

## Environment and scope

- Tested upstream commit: `677345b0933f5f8754aeec3125d14df32683ca97`.
- macOS 27.0.1, Apple M2 Max, arm64 Mac host.
- The Legend of Zelda: Echoes of Wisdom, update 1.1.0, base title ID `01008CF01BAAC000`, SDK 20.5.1.
- Main module build ID: `9f221e1afa65ba5443e955158ab97da8`.
- Generated provisional profile; no claim of full game compatibility.
- Host includes six launcher patches for input/window preferences, explicit memory overrides, touch diagnostics and language fallback. Those patches do not modify `hle_sdk16.c`, the font engine, shader tools or the Metal texture-view path. Identical local patches and game resources were used in the A/B comparison.
- The original exported modules were reused in both runs; this is an updated-host comparison, not a full rewrite/shader rebuild on the new upstream revision.

## Failure

The default shared-font heuristic in `dm/host/hle_sdk16.c` selects BFTTF header plus TTF for a modern SDK whose main module imports `ScalableFontEngineHelper::Decode`.

This main imports Decode, but its font initialization calls it only for descriptors satisfying `(type & ~1) == 2`. All six observed shared-font descriptors were type 0. They skip Decode and pass the shared-font address directly to `ScalableFontEngine::LoadFont`.

With default presentation, both engine initialization checks return 0, but both LoadFont error checks return 403 for all six fonts. Subsequent SetFont error checks return 301. Glyph lookup for U+25A1 returns null, followed by:

```text
CRASH sig=11 addr=0x38 pc=main+0x8b37c
x0=0
```

The faulting instruction is `ldrb w8, [x0, #0x38]`. The standard substitute is Arial Unicode MS and its cmap contains U+25A1, so an absent square in the standard font is not the first failure. Error 403 is an observed numeric code; its enum name is not asserted here.

## Controlled result

I copied the generated provisional profile and added the already supported setting:

```tsv
shared_font	ttf
```

I compiled a second host at the same source revision, with unchanged rewritten modules, font files and shader/RomFS resources. Each run used fresh isolated save, temp, root, PSO and home paths, identical probes and a 20-second bound.

| Observation | Default heuristic | Explicit `shared_font ttf` |
|---|---|---|
| Initialize GetError | 0 | 0 |
| LoadFont GetError, primary and per-engine sites | 403, six hits at each | 0, six hits at each |
| Initial SetFont GetError | 301, six hits | 0, six hits |
| Glyph-selection SetFont GetError | 301 | 0 |
| Shared descriptor types | 0, six records | 0, six records |
| Decode return probe hits | 0 | 0 |
| Null lookup at `main+0x8b37c` | Reproduced | Passed |

The TTF candidate reaches frame 3, audio and save initialization, then stops at a **different** Metal texture-view assertion: a requested mip-level range ends at 8 while the source texture has 7 mipmap levels, in `tex_by_id` through `encode_args_` and `mtl_exec`. Therefore this fixes the font bring-up stage only; the title is not yet verified playable.

## Probe recipe

For the exact main build ID above, these instructions were checked to be position-independent, nonbranch and safe for the Mac probe trampoline's x16 clobber:

```sh
DM_PROBE=main:8d0f4,main:8d170,main:8d544,main:8d588,main:8d5cc,main:8db48,main:8f524,main:8d220,main:8d24c,main:8d534
```

- `8d0f4`, `8d170`: GetError after Initialize.
- `8d544`, `8d588`: GetError after LoadFont.
- `8d5cc`, `8db48`, `8f524`: GetError after SetFont.
- `8d220`: x8 holds the descriptor type before the mask/test.
- `8d24c`: reached only after Decode; zero hits in both runs.
- `8d534`: x2 is the actual buffer about to be passed to LoadFont.

GetError resolves to `sdk+0x377f50`, `ldr w0, [x0, #0x48]; ret`, so the first seven sites observe a zero-extended 32-bit error code. These offsets must not be reused on another build without validation.

Build the copied profile by exporting profile discovery variables to make's environment:

```sh
DM_GAMES_DIR='<diagnostic profile root>' DM_GAMES_FIRST=1 \
  make -C dm/host GAME=01008CF01BAAC000
```

## Proposed upstream handling

The smallest verified correction is the existing `shared_font ttf` profile override for this consumer, with the title kept provisional until later blockers are resolved. Documentation should clarify that importing Decode does not prove shared fonts use it: a single game may import it for other descriptor types.

A general heuristic improvement should use evidence of the shared-font consumer's behavior, rather than treating any Decode import as sufficient. This report does not propose switching every SDK 20 title to raw TTF: games that actually call Decode need the BFTTF representation. It also does not propose bypassing the null dereference or declaring a complete game port.

The next Metal issue should be investigated separately using the texture's source mip count and requested guest view range, with the export's shader-table completeness accounted for before assigning a root cause.

No keys, game executable bytes, game assets, font binaries, memory dumps or personal filesystem paths are included in this draft.

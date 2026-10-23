# Echoes of Wisdom: font bring-up investigation

Status: the font-stage correction has been verified by controlled A/B testing; full game compatibility is not established. The minimal host-owned-buffer fix is submitted as [upstream PR #55](https://github.com/seedds/nxnative/pull/55), commit `951d6ff918dfd68dbdcb76dac6e2eaf0a191eb45`, based on clean upstream `e18a9fd`.

## Builds and upstream baseline

- Game: The Legend of Zelda: Echoes of Wisdom, update 1.1.0, title ID `01008CF01BAAC000`.
- Main module build ID: `9f221e1afa65ba5443e955158ab97da8`.
- Initial exported host baseline: `26a72dd5620ff8ea4a0ad23240e401e3802b2c7b`, with the launcher's local patch series.
- Tested update: upstream `677345b0933f5f8754aeec3125d14df32683ca97` plus the six retained launcher patches.
- The generated game profile is provisional. Neither a successful export nor this investigation establishes playability.

The upstream update adopts the launcher's mouse routing and JSON progress contributions as `b302d40` and `f1c4a6b`, respectively. It does not change the shared-font presentation decision in `hle_sdk16.c` or add an official profile for this title. A new launcher build does not update an already exported game host or rewritten modules.

## Confirmed initial failure

Three existing launches entered `nnMain`, initialized Metal and submitted frames, then failed at the same guest-relative address:

```text
CRASH sig=11 addr=0x38 pc=main+0x8b37c
x0=0
backtrace: main+0x267e52c main+0x341328 main+0x361028
```

The instruction at `main+0x8b37c` is `ldrb w8, [x0, #0x38]`. The null base explains the fault address exactly. The function starts at `main+0x8b33c`; its lookup at `main+0x8f1f8` returned null. The caller prepares character U+25A1 (WHITE SQUARE), with size `0x2a`.

The lookup reaches `nn::fontll::ScalableFontEngine::CheckGlyphExist(unsigned)`. Stack-scan addresses agree with that path, but stack-scan words are supporting evidence rather than an unwound call stack. The available host dSYM matches UUID `AF67CC2B-DBB1-39FE-AFD6-7061D8358018`; guest functions have no source-line mapping in the available artifacts.

Immediately before the fault, the host opened the exported standard and extended font substitutes and selected BFTTF-header-plus-TTF presentation for SDK 20. The guest contains a conditional call to `ScalableFontEngineHelper::Decode`: a descriptor-type test, `(type & ~1) == 2`, at `main+0x8d21c` through `0x8d234` controls the call at `0x8d248`. The presence of that call does not prove the shared-font path executes it. Both a presentation mismatch and a later font-engine failure remain possible until runtime probes distinguish them.

The host handles SIGSEGV and exits with 139 rather than re-raising the signal, explaining why a normal system crash report may be absent.

## Substitute-font coverage

Metadata inspection of the exported substitute fonts found U+25A1 in `standard.ttf` (Arial Unicode MS, glyph `H22073`, Windows Unicode BMP cmap format 4). The 29-glyph `nintendo_ext.ttf` stand-in does not include U+25A1. This rules out an absent square in the standard substitute, but does not establish which font the engine selects at failure or whether the standard font loaded successfully.

## Targeted diagnostics

Use the existing Mac `DM_PROBE` support to inspect the low 32 bits of x0 after `GetError()` calls following initialization, `LoadFont` and `SetFont`. A probe observes registers before executing its replaced instruction. It clobbers x16, so probe sites must be verified by disassembly: no PC-relative instruction or branch, and x16 must be dead there. Fixed offsets are valid only for the build ID above.

Verified return sites (all use position-independent loads, with no read of incoming x16 before its redefinition or a call boundary). `GetError` resolves to `sdk+0x377f50`, `ldr w0, [x0, #0x48]; ret`, so x0 holds a zero-extended 32-bit error field:

| Phase | Guest offsets |
|---|---|
| Initialization | `main:8d0f4`, `main:8d170` |
| LoadFont | `main:8d544`, `main:8d588` |
| SetFont | `main:8d5cc`, `main:8db48`, `main:8f524` |

Run probes with independent save, temp, user PSO, root, working directory and home paths under the game's work directory. Keep the original exported bundle and normal saves unchanged. Set explicit read-only bundle paths for RomFS, rewritten modules, shader tables/libraries and substitute fonts. Bound execution externally and preserve the exact environment and output. Compare the original host with a separately compiled updated host before claiming an upstream result.

## Isolated baseline reproduction

A headless direct run of the original exported host with the seven verified probes exited with 139 in 0.343 seconds and reproduced `main+0x8b37c`, null x0, character U+25A1. It used fresh home, root, save, temp, PSO and working-directory paths under the game's work directory. The original bundle and normal saves were not modified.

| Phase | GetError result | Observations |
|---|---|---|
| Initialize | `0` | Both initialization sites |
| LoadFont | `0x193` (403) | Six hits at each of `8d544` and `8d588`, all nonzero |
| Initial SetFont | `0x12d` (301) | Six hits at `8d5cc` |
| Glyph-selection SetFont | `0x12d` (301) | Twelve hits at `8f524`, including U+25A1 |
| Alternate SetFont path | Not reached | `8db48` |

A second isolated run added verified probes at `main:8d220` (descriptor type in x8), `main:8d24c` (Decode return) and `main:8d534` (LoadFont input). All six descriptors had type `0`; the Decode return probe had zero hits. The first five LoadFont calls received the same standard-font buffer, and the sixth received the extension buffer. LoadFont again reported 403, SetFont 301, and the same null lookup crashed. Thus the game's actual shared-font path skips Decode, while the host's SDK/import heuristic selects BFTTF presentation. The analogous failure is already documented for Super Mario 3D World in upstream `hle_sdk16.c`.

The earliest observed failure is font loading, before the null glyph lookup. Error numbers are reported as observed; their symbolic meanings have not yet been established. The existing profile setting `shared_font ttf` is a narrow A/B candidate. These runs are original-host evidence, not yet execution results for the updated upstream host.

## Updated-host control

A separately compiled host at upstream `677345b` plus the six retained launcher patches reproduced the same failure using the unchanged exported modules, fonts and resources. Initialization returned 0, all six descriptors were type 0, Decode had no hits, LoadFont returned 403 at both observed sites, SetFont returned 301, and the null lookup crashed at `main+0x8b37c`. The control exited with 139 in 1.153 seconds. Its SHA-256 is `89c4bd9664de25686bedfbb502f75555952c5fcda9315ee2f737581eda75299e`.

For a controlled candidate, copy the provisional profile to a diagnostic directory and add `shared_font\tttf`, then compile another host. Export `DM_GAMES_DIR` and `DM_GAMES_FIRST=1` in the process environment, rather than passing them only as make command-line variables: profile discovery invokes Python during Makefile parsing. Preserve both hosts and use identical probes/resources with fresh writable scratch for each run.

## TTF candidate result

The updated host compiled against the diagnostic profile copy with `shared_font ttf` emitted `DM_GAME_SHARED_FONT_TTF 1`. Its SHA-256 is `e33cbca1407cf576a1853666fa72cbeb21f96dcfb7f5118cda26166b09d1785b`.

Using the same resources and probes, all observed font error values became zero:

| Phase | Default host | TTF profile host |
|---|---|---|
| Initialize | 0 | 0 |
| LoadFont, both sites | 403, six hits each | 0, six hits each |
| Initial SetFont | 301, six hits | 0, six hits |
| Glyph-selection SetFont | 301 | 0 |
| Original `main+0x8b37c` fault | Reproduced | Not encountered |

The candidate passed the original failure and reached frame 3, audio and save initialization. It then exited with 134 in 1.274 seconds at a separate Metal texture-view assertion: the requested mip-level range ended at 8, but the source texture had 7 mipmap levels (`tex_by_id` through `encode_args_` and `mtl_exec`). This establishes a font-stage correction, not overall game compatibility. The two diagnostic save commits were confined to the fresh scratch save directory. No existing saves or exported bundle were changed.

Artifacts are under the game's `01008CF01BAAC000-work/diagnostics/`:

- `run_font_probe.py`: bounded, isolated runner; validates build ID, opcodes and an allowlist of safe probes before launching.
- `hosts/default/dmhost` and `hosts/ttf/dmhost`: preserved comparison binaries and symbols.
- `font-geterror-20261022-180002-453514/`: updated default `results.json` and `stdout.log`.
- `font-geterror-20261022-180115-492613/`: TTF candidate `results.json` and `stdout.log`.
- `profile-ttf/01008CF01BAAC000/`: copied provisional profile with the single explicit font override.

No active game profile or global font policy was changed. A separate upstream report draft is in `upstream-echoes-font-report.md`.

## Minimal upstream fix (PR #55)

The follow-up runs use clean upstream `e18a9fd`, without launcher patches and without the TTF profile override. The control still reports LoadFont error 403, SetFont error 301 and the original null-pointer fault. The candidate normalizes only exact host-owned BFTTF allocation bases at the existing `ScalableFontEngine::LoadFont` symbol, then forwards to the original guest implementation. Shared-font presentation, Decode, payload bytes, face index, output-name capacity and SDK error propagation remain unchanged.

The exact symbol is `_ZN2nn6fontll18ScalableFontEngine8LoadFontEPcPKvjj`. Bounded dynamic-symbol and instruction inspection establishes the data-pointer argument, the zero-based TTC face index, the output-name capacity and the raw 32-bit status-return ABI. The TTC index selects `header + 0xC + index * 4` after checking the TTC face count; it is not a font-buffer byte length.

The candidate returns zero from every observed font error query and passes the original fault, then encounters the same independent Metal mip-range assertion seen with the explicit TTF profile. The focused review found no blockers. No exported app or original profile was replaced by this PR.

Additional local artifacts under the same diagnostics directory:

- `font-geterror-20261022-182432-003075/`: clean upstream control; host SHA-256 `518364d60150779e9b708ce2b06bbd8ea635e5f9290be405dbb83e1b93ca61e8`.
- `font-geterror-20261022-183452-504598/`: minimal candidate; host SHA-256 `cea447c4bc4449396b9be56880b81e3b877664fb1d3c5e2115a561b53d8b823f`.
- `hosts/clean-e18a9fd/` and `hosts/font-candidate-e18a9fd/`: preserved hosts and symbols.
- `tests-font-candidate.log`: all 15 upstream host test programs pass, including 137 new font checks.
- `botw-control-20261022-182632-611385/` and `botw-control-20261022-183638-690488/`: original and candidate Breath of the Wild startup checks; both run 20 seconds to at least frame 900. The candidate binds the new hook, but neither run requests shared fonts, so these are not runtime Decode-path coverage.

Mac and iOS arm64 strict syntax checks pass. The PR contains only `hle_sdk16.c`, `tests/t_shared_font.c` and `tests/Makefile`; no game resources, logs, fonts, keys or generated profile are published. The hook covers relocations for this overload, not direct intra-module calls or original addresses obtained through `nn::ro::LookupSymbol`.

## Contribution criteria

First distinguish font initialization/load/selection errors, missing glyph coverage, and a later glyph/cache failure. Prefer a general correction to shared-font or SDK semantics with a no-game regression test. If a build-specific rule is unavoidable, key it by the full module build ID and explain why a general rule cannot work.

Do not submit a null-check bypass as a compatibility fix without proving the expected fallback behavior. If no tested fix is available, an upstream issue with the module build ID, narrow offsets, error values, probe recipe and a small sanitized log excerpt is the appropriate contribution. Exclude keys, game executables/assets, font binaries and personal paths.

The export's resource-seal problem, minimum-OS metadata mismatch and omitted `cb_extent.tsv` are separate findings. They are not established causes of this CPU font-path fault.

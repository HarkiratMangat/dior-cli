# `dior gif` — bridging the gif-background-remover skill into the CLI

*Designed and built 2026-09-03. Branch `feat/gif-bridge`.*

*Spec location note: Diors-Builds puts these under `docs/superpowers/specs/`. This repo has ten files and an empty `docs/`, so a three-level nest for one document would cost more than it explains. Flat here, deliberately.*

## The problem as stated, and why that framing turned out to be wrong

The ask was: the skill has a lot of flags, most of them confusing, and using it without an AI agent is hard — so build a bridge that makes it usable by someone who has never met it.

The obvious reading is "expose 64 flags nicely." That reading is wrong, and testing it first is what shaped everything below.

`--auto` already exists. It runs the skill's own `--recommend`, applies its flags **only where you left that option at its default**, renders, re-measures the written file, and re-renders once if the encoded result disagrees with the pre-encode calibration. A person who types `--auto` never touches any of the other 63 flags. So the flag count is not the friction on the happy path.

The friction is three questions, and none of them is a flag-count problem:

1. **`--auto` refuses a coin-flip protection decision.** When a candidate region's outline encloses it on *some* frames but not all, whether that enclosed interior is design or background is a statement about intent, and the pixels do not answer it. Measured across 304 real assets: **12.8%** refuse this way. The refusal names the region, its bbox, its outline colour and the frame counts — as prose. *Nobody can answer `bbox [230,135,406,359], outline 002864` from text.*
2. **`--auto` refuses a nameable fade** it can identify but not classify, for a measured reason: across the 91 assets in that branch, the ramp statistics interleave with assets that render as a translucent ghost of the whole frame, so no threshold separates them.
3. **The size/format goal**, which the tool deliberately never guesses. SKILL.md is explicit that a guessed target is the worst measured failure in the skill's history, because it produces a real file at a real size and nothing downstream says the number was invented. The 2026-08-19 trial measured the consequence: **variant sprawl was inversely proportional to how much the user had constrained the goal.**

So the bridge is an **interview**, not a flag surface.

## The finding that made it cheap: the skill is already a question API

`--recommend` returns all three questions as structured JSON, before anything is rendered:

| field | carries |
|---|---|
| `ambiguous_protection` | a list of `{region_id, outline_color, bbox_xyxy, frames_enclosed, frames_checked, enclosure_ratio}` |
| `nameable_fade` | `{color, faint_px, frame_index}` |
| `recommended_format` | one of `gif-ok`, `webp-or-apng`, `webp-or-avif` |
| `not_applicable_reason` / `alternative_command` | why it refuses outright, and what to run instead |
| `evidence` | human-readable justification, one string per finding |

`--auto` derives its refusals from exactly those same fields (`remove_gif_background.py:9778`, `:9810`). So a wrapper that calls `--recommend` **first** sees every question in advance, answers them via `--assume-protect` / `--assume-remove` / `--fade-color` / `--assume-no-fade`, and then calls `--auto` — which never refuses, because nothing is left to refuse.

**This is why the design needs zero changes to the skill.** Its JSON is already machine-readable; nothing here reaches inside it, and nothing in the skill package knows this CLI exists.

## Shape

Two halves, matching the split `text unwrap` → `scripts/reflow-prose.mjs` already established in this repo:

- **`gif.zsh`** owns the surface — registration, the menu entry, the guides, tab-completion, argument validation, and exporting the `DIOR_C_*` palette so the Python half prints in the same colours rather than inventing a second visual system.
- **`scripts/gif_wizard.py`** owns the engine — `--recommend`, the questions, preview rendering, flag assembly, the render, verification, and reporting. Python because the work is JSON parsing, PIL image cropping and subprocess orchestration; zsh would be fragile at all three.

Three commands, following the CLI's grammar (bare word = mode, `--flag` = combinable):

```
dior gif clean   <file...> [--to <preset>] [--out <dir>] [--yes] [--no-preview]
dior gif check   <file...> [--why]
dior gif presets
```

`dior gif` bare prints the group's subcommand list, because `clean` writes files.

`DIOR_GIF_DIR` in `core.zsh` points at the dev repo — the same shape and the same reasoning as `DIOR_BOT_DIR`, so the CLI exercises the working tree. If it is missing, the wizard falls back to the bundle claude.ai syncs onto this machine **and says which one it used**; a silent fallback would let the CLI and the live skill disagree invisibly. `dior doctor` checks both that and Pillow.

## The visual answer

The coin-flip question is the one that decides whether a non-expert can use this at all, and it cannot be asked in words. `ambiguous_protection` carries `bbox_xyxy`, and PIL is already a dependency of the skill, so the wizard crops that region out of **three sampled frames** (first, middle, last), composites each over a checkerboard, draws a pink box on the bbox, upscales, writes one PNG and opens it.

Three frames rather than one, deliberately: the entire reason the region is a coin flip is that its enclosure *changes* across the animation, so a single still is the one view guaranteed not to show what the question is about.

The question then reads: *"Should the area inside the pink box be see-through, or stay filled in?"* — which anyone can answer by looking.

The fade question shows the **whole** frame `nameable_fade.frame_index` instead of a crop, because a fade is diffuse and cropping to a bbox would remove the thing being asked about.

`--no-preview` suppresses both; `--yes` skips the interview entirely and prints every assumption it made, because an assumption that leaves no trace is indistinguishable from a measurement.

## Presets: goals, not settings

`--to` is the only channel through which a size or format constraint ever reaches the tool. The default applies **no compression flags at all**, matching SKILL.md's size gate case 1. A large output is named and offered; offering is not acting.

| preset | expands to |
|---|---|
| `full` *(default)* | nothing |
| `discord-emoji` | `--format avif --resize-max-dim 128 --avif-quality 85 --target-kb 250 --min-quality 70` |
| `under-256kb` | `--avif-quality 85 --target-kb 250 --min-quality 70` |
| `under-<N>kb` | the same, with `N` |
| `gif` / `webp` / `avif` / `apng` | `--format X` |

**Every number is cited from the skill repo, never invented.** Discord's emoji cap is 256 KB (exact error `[50138] ... 262144` bytes); `--target-kb` multiplies by 1024, so 256 sits exactly on the limit and 250 buys honest margin rather than betting on `<` versus `<=`. "AVIF at 128×128, keeping every frame, trying q85 then q70" is the measured cascade, and `--avif-quality 85 --min-quality 70` reproduces exactly that ladder and nothing wider.

The `--avif-quality 85` is not decoration. `--target-kb` is a **ceiling that never spends unused headroom** — passing it alone was measured delivering 99.8 KB at q70 with 150 KB of a 250 KB cap unused. Writing the preset the naive way would have reproduced a bug the repo had already documented.

**There is deliberately no `discord-sticker` preset.** Discord stickers are also 256 KB, but the repo records no dimension for them, and inventing 320×320 to make a name look complete is exactly the guess this whole design exists to prevent. `under-256kb` covers that case and lets `--target-kb`'s own ladder pick the largest resolution that fits.

## Two defects found by testing, both of the same kind

The first end-to-end run *looked* correct and was not.

**`report_verify` read three fields at the wrong type.** `leftover_background_opaque_px` is a dict (`max_per_frame`), not a number; `protected_region_coverage` is a **list** of per-region dicts, not one dict; `timing` is a **string**, not a dict. All three `isinstance` guards fell through, so the function printed *"background gone everywhere, protected parts intact, no pale fringe, timing unchanged"* without having looked at any of it. On the very first asset, the JSON said two regions were `looks_unprotected: true`. A check that cannot fail is worse than no check, because it manufactures confidence — and the previous version carried a comment warning against precisely that failure while committing it.

**`--verify` was not being told what the run had been told.** `verify()` takes `assume_remove_colors` and uses it to drop the regions the run was *instructed* to remove. Without it, an interior the person explicitly asked to be see-through comes back as unprotected and reads as a defect. Measured on the megaphone asset: two of its three regions report exactly that.

Both are now fixed against the real shape, and anything absent is reported as **not checked** rather than as passing. `checks_skipped` (and `dimensions_match`) drive an explicit warning, because `--verify` skips every pixel check when the output was cropped or resized — so a tick after a resize would be vacuous.

## What the run costs, and one duplication left open

Measured on a 144-frame 640×640 asset: `--recommend` ≈ 18s, `--auto` ≈ 60s (it re-runs `--recommend` internally), `--verify` ≈ 30s. Every wait is narrated with a phase, because half a minute of dead terminal reads as a hang.

`--auto` runs the identical `verify()` internally and prints its key fields as prose (`remove_gif_background.py:10026`). Running `--verify` again is therefore a genuine duplicate — paid because a **structured** verdict is the only kind worth printing a tick next to, and parsing prose to make a correctness claim is not something to build on. Closing it properly would mean a way for `--auto` to hand its internal verify JSON to a caller, which is a change to the skill and out of scope here. Filed in that repo's own tracker rather than left unrecorded.

`--auto`'s raw stderr is captured rather than passed through: nine lines of `evidence: A SOLID art colour sits 57 from the background, inside the default feather band (15..60)` is correct and useful output for the agent it was written for, and is exactly what this CLI exists to stand in front of. The full log is kept and printed verbatim **when the run fails**, because at that point the jargon is the only thing that can explain why.

## One fix outside the feature

`_dior_suggest` gated its "right group, wrong subcommand" branch on a literal `[ "$group" = "bot" ]`, so `dior legal`, `dior text`, `dior docs` and `dior emoji` all fell past it to the generic *"isn't a recognized dior command"* plus the entire menu — when the useful answer, their own subcommand list, was one array scan away. It is the same defect the comment above `_dior_show_help` describes fixing on the help side and never fixed here. Adding a fifth group made it visible; it was wrong for the other four already. Now derived from `DIOR_MENU_ORDER`, with a space test so a single-word entry like `changelog` cannot answer itself.

Before/after diff over all eight groups: five fixed, `bot`, `changelog` and an unknown word unchanged.

## Testing

There is no test runner here, so this was verified by execution:

- `zsh -n` on every changed file.
- Rendered-output diff of bare-group dispatch across eight groups, before and after the suggester change.
- Unit checks of the risky Python: both region previews render, the fade frame renders, `_transparent` → `_v2` → `_v3` escalation actually escalates, every preset resolves, and an unknown preset is refused rather than silently accepted.
- **The interview driven through a real pty**, not a pipe. A pipe is not enough: the wizard gates the interview on `sys.stdin.isatty()`, so a piped run silently takes the non-interactive branch and would "pass" without ever asking a question — a vacuous test of exactly the path that matters.
- Real end-to-end renders on a coin-flip asset (megaphone, 144 frames, two ambiguous regions) and a clean one (rocket, 177 frames, none), plus a resize path to exercise the skipped-checks branch.

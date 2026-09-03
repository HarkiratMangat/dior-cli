#!/usr/bin/env python3
"""Falsifiers for gif_wizard.py's pure logic. Run: python3 scripts/test_gif_wizard.py

WHY THIS FILE EXISTS
--------------------
The first version of `report_verify` read three fields at the wrong type --
`leftover_background_opaque_px` is a dict, `protected_region_coverage` is a list,
`timing` is a string -- so all three `isinstance` guards fell through and it printed
"background gone everywhere, protected parts intact, no pale fringe, timing unchanged"
without having looked at any of it. On the very first real asset, the JSON it was
ignoring said two regions had come out unprotected.

A check that cannot fail is worse than no check, because it manufactures confidence.
So EVERY case below is PAIRED: one input where the check must fire and one where it
must stay quiet. A suite that only ever asserts the happy path would have passed
against the broken version.

The fixtures are the real shapes, copied from actual `--verify` output on two assets
(a same-size GIF and a resized AVIF), not invented. Nothing here renders or shells
out, so it runs in well under a second and can be run on every edit.
"""

import copy
import io
import sys
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gif_wizard as W  # noqa: E402

FAILURES = []


def check(name, condition, detail=""):
    if condition:
        print("  ok    %s" % name)
    else:
        print("  FAIL  %s %s" % (name, detail))
        FAILURES.append(name)


def report(v):
    """Capture report_verify's output as one string."""
    buf = io.StringIO()
    with redirect_stdout(buf):
        W.report_verify(v)
    return buf.getvalue()


# ---------------------------------------------------------------------------
# Fixtures — the real shapes, from actual --verify runs.
# ---------------------------------------------------------------------------
CLEAN = {
    "dimensions_match": True,
    "checks_skipped": [],
    "frame_alignment": "exact",
    "leftover_background_opaque_px": {"max_per_frame": 0, "worst_frame_index": 0,
                                      "total_frames_with_any": 0},
    "output_format": "gif",
    "edge_fringe_check": {"mean_fringed_pixel_fraction": 0.0055, "looks_fringed": False},
    "protected_region_coverage": [
        {"region_id": 2, "mean_opacity_fraction": 1.0, "looks_unprotected": False},
    ],
    "unprotected_design_regions": [],
    "small_region_inflation": {"flagged": [], "flagged_count": 0},
    "timing": "144 frames, durations preserved exactly",
    "verified": True,
}

# A resized output: every pixel check is skipped, and the encoder coalesced frames.
RESIZED = {
    "dimensions_match": False,
    "checks_skipped": ["pixel checks skipped: output 128x128 differs from source 640x640 "
                       "(--crop or --resize-max-dim). Nothing about the ARTWORK was checked."],
    "frame_alignment": None,
    "leftover_background_opaque_px": {},
    "output_format": "avif",
    "edge_fringe_check": {},
    "protected_region_coverage": [],
    "timing": "89 frames written from 177 intended -- 88 identical frame(s) coalesced by "
              "the encoder, total playback unchanged at 3600ms",
    "verified": False,
}


def mutate(base, fn):
    v = copy.deepcopy(base)
    fn(v)
    return v


print("report_verify — every check must fire on a bad input and stay quiet on a good one")

# --- the two real cases -----------------------------------------------------
clean_out = report(CLEAN)
check("clean output reports a pass", "Checked:" in clean_out and "problems" not in clean_out)
check("clean output does not warn about skipped checks", "did NOT run" not in clean_out)

resized_out = report(RESIZED)
check("resized output NAMES the skipped pixel checks", "did NOT run" in resized_out)
check("resized output does not claim a clean bill of health",
      "background gone everywhere" not in resized_out)
# ⚠️ The paired half that matters: encoder frame-coalescing with total playback
# unchanged is NOT a defect (SKILL.md says so), and the first version reported it
# as one on a real asset.
check("coalesced frames with unchanged playback are NOT reported as a problem",
      "playback timing changed" not in resized_out, repr(resized_out))

# --- leftover background ----------------------------------------------------
check("leftover background FIRES",
      "background pixels are still solid" in report(mutate(
          CLEAN, lambda v: v["leftover_background_opaque_px"].__setitem__("max_per_frame", 812))))
check("leftover background QUIET at zero",
      "background pixels are still solid" not in clean_out)
# The original bug: a dict read as a number. Guard the shape itself.
check("leftover background survives a missing dict",
      "Checked" in report(mutate(CLEAN,
                                 lambda v: v.__setitem__("leftover_background_opaque_px", None))))

# --- protected regions ------------------------------------------------------
check("unprotected region FIRES",
      "came out see-through" in report(mutate(
          CLEAN, lambda v: v.__setitem__("unprotected_design_regions",
                                         [{"region_id": 2}]))))
check("unprotected region QUIET when none", "came out see-through" not in clean_out)
# protected_region_coverage is a LIST; the first version treated it as a dict and
# never fired. Prove the fallback path (no pre-filtered key) reads the list.
check("falls back to the per-region LIST when unprotected_design_regions is absent",
      "came out see-through" in report(mutate(
          CLEAN, lambda v: (v.pop("unprotected_design_regions"),
                            v["protected_region_coverage"].append(
                                {"region_id": 9, "looks_unprotected": True})))))

# --- fringe -----------------------------------------------------------------
check("fringe FIRES",
      "pale fringe" in report(mutate(
          CLEAN, lambda v: v["edge_fringe_check"].__setitem__("looks_fringed", True))))
check("fringe QUIET when clean", "found problems" not in clean_out)

# --- small-region inflation -------------------------------------------------
check("small-region inflation FIRES",
      "got eaten" in report(mutate(
          CLEAN, lambda v: v.__setitem__("small_region_inflation", {"flagged_count": 3}))))
check("small-region inflation QUIET at zero", "got eaten" not in clean_out)

# --- art loss / empty output ------------------------------------------------
check("art-loss warning FIRES",
      "did not survive" in report(mutate(
          CLEAN, lambda v: v.__setitem__("opaque_survival_warning",
                                         "28% of the artwork did not survive"))))
check("empty output FIRES",
      "fully transparent" in report(mutate(
          CLEAN, lambda v: v.__setitem__("output_is_empty",
                                         "every frame is fully transparent"))))

# --- timing -----------------------------------------------------------------
check("a REAL timing defect FIRES",
      "playback timing changed" in report(mutate(
          CLEAN, lambda v: v.__setitem__(
              "timing", "This is a real timing defect, not encoder frame-coalescing."))))
check("an UNKNOWN timing wording FIRES rather than passing quietly",
      "playback timing changed" in report(mutate(
          CLEAN, lambda v: v.__setitem__("timing", "something nobody has written yet"))))
check("durations preserved exactly is QUIET", "playback timing changed" not in clean_out)

# --- no report at all -------------------------------------------------------
check("a missing verify says so", "Couldn't run" in report(None))

# --- dimensions_match as a fallback signal ----------------------------------
check("a size mismatch with an EMPTY checks_skipped still warns",
      "did NOT run" in report(mutate(
          CLEAN, lambda v: (v.__setitem__("dimensions_match", False),
                            v.__setitem__("checks_skipped", [])))))


print()
print("presets — every number is cited, and an unknown name is refused")

for name in W.PRESETS:
    check("preset %s resolves" % name, isinstance(W.preset_flags(name), list))
check("full applies NO compression flags", W.preset_flags("full") == [],
      repr(W.preset_flags("full")))
# ⚠️ --target-kb is a CEILING that never spends unused headroom, so a cap preset that
# omits the starting quality delivers whatever the default was -- measured at 99.8 KB
# against a 250 KB cap. Both cap presets must pass the top of the range explicitly.
for name in ("discord-emoji", "under-256kb", "under-500kb"):
    fl = W.preset_flags(name)
    check("%s passes an explicit starting quality" % name, "--avif-quality" in fl, repr(fl))
    check("%s passes a quality floor" % name, "--min-quality" in fl, repr(fl))
    check("%s passes a byte cap" % name, "--target-kb" in fl, repr(fl))
check("discord-emoji pins 128px", W.preset_flags("discord-emoji")[
    W.preset_flags("discord-emoji").index("--resize-max-dim") + 1] == "128")
check("a custom cap carries its own number",
      W.preset_flags("under-500kb")[W.preset_flags("under-500kb").index("--target-kb") + 1] == "500")

for bad in ("discord-sticker", "small", "under-kb", "under-0kb", ""):
    try:
        W.preset_flags(bad)
        check("unknown preset %r is refused" % bad, False, "it was accepted")
    except ValueError:
        check("unknown preset %r is refused" % bad, True)


print()
print("output naming — an already-delivered file is never overwritten")

import tempfile  # noqa: E402
td = tempfile.mkdtemp(prefix="gifwiz-test-")
names = []
for _ in range(3):
    p = W.output_path("/somewhere/art.gif", "gif", td)
    p.touch()
    names.append(p.name)
check("escalates rather than overwriting",
      names == ["art_transparent.gif", "art_transparent_v2.gif", "art_transparent_v3.gif"],
      repr(names))
check("honours the extension",
      W.output_path("/somewhere/other.gif", "webp", td).name == "other_transparent.webp")


print()
print("format mapping — every value the tool can return has an extension")

# The three values recommended_format can take, read out of the skill's source.
for verdict in ("gif-ok", "webp-or-apng", "webp-or-avif"):
    check("%s maps to an extension" % verdict, W.FORMAT_EXT.get(verdict) in ("gif", "webp"))
check("an unknown verdict falls back rather than crashing",
      W.FORMAT_EXT.get("something-new", "gif") == "gif")


print()
if FAILURES:
    print("%d FAILED: %s" % (len(FAILURES), ", ".join(FAILURES)))
    sys.exit(1)
print("all checks pass")

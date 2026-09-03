#!/usr/bin/env python3
"""
dior gif — the bridge between the gif-background-remover skill and a human.

WHY THIS EXISTS
---------------
The skill exposes 64 flags. That count is not actually the friction: `--auto` already
runs `--recommend`, applies its flags, renders, re-measures and re-renders once, so the
happy path never needs any of the other 63. The real friction is that `--auto` REFUSES
on two classes of question it will not guess at, and those refusals arrive as prose
naming hex colours and bounding boxes:

  1. COIN-FLIP PROTECTION (12.8% of assets, measured over 304) -- "is the region at
     bbox [412,180,470,238], outlined in f0c850, interior design or background showing
     through?"  Nobody can answer that from text. They have to SEE it.
  2. NAMEABLE FADE -- "is this soft falloff artwork, or not?"

...plus a third question the tool deliberately does NOT ask, because guessing it is the
single worst measured failure mode in the skill's history: the size/format goal.

`--recommend` already returns all three as STRUCTURED JSON (`ambiguous_protection` with
bboxes, `nameable_fade` with a frame index, `recommended_format`). So this wrapper reads
the questions BEFORE running anything, asks them in plain English -- opening a
highlighted crop in Preview for the visual ones -- and then calls `--auto` with the
answers already supplied, so `--auto` never refuses.

That is why this needs ZERO changes to the skill. The skill's JSON is already a
machine-readable question API; nothing here reaches inside it.

WHAT THIS DELIBERATELY DOES NOT DO
----------------------------------
It never infers a size target. SKILL.md's "size/format gate" is explicit that a guessed
target is invisible downstream and that variant sprawl is inversely proportional to how
constrained the goal is. So the default preset is `full` -- no compression flags at all --
and a size target only ever comes from the human picking one. The CLI reports the output
size and OFFERS, exactly as the skill instructs. Offering is not acting.

It also never reports a vacuous verification. `--verify` skips every pixel check when the
output was cropped or resized, and says so only in a `note` field; this prints that fact
rather than a green tick.

Written 2026-09-03. Driven by ~/.config/dior/gif.zsh; not part of the skill package.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

# ---------------------------------------------------------------------------
# Colours. dior's palette is 256-colour indices set in core.zsh; gif.zsh exports
# them so this script and the rest of the CLI stay one visual system. Falling
# back to our own copies keeps the script runnable standalone (and testable).
# ---------------------------------------------------------------------------
_TTY = sys.stdout.isatty()


def _c(name, fallback):
    if not _TTY:
        return ""
    return os.environ.get("DIOR_C_" + name, fallback)


RESET = _c("RESET", "\033[0m")
TITLE = _c("TITLE", "\033[1;38;5;197m")
FOOT = _c("FOOT", "\033[2;38;5;197m")
HEAD = _c("HEAD", "\033[1;38;5;141m")
CMD = _c("CMD", "\033[38;5;87m")
ARG = _c("ARG", "\033[38;5;49m")
OPT = _c("OPT", "\033[38;5;183m")
HELP = _c("HELP", "\033[38;5;230m")
WARN = _c("WARN", "\033[1;38;5;227m")
ERROR = _c("ERROR", "\033[1;38;5;196m")
OK = _c("OK", "\033[1;38;5;82m")
DIM = _c("DIM", "\033[2m")


def out(msg=""):
    print(msg, flush=True)


def err(msg):
    print(msg, file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# Presets — the size/format gate, expressed as goals rather than flags.
#
# EVERY number here is cited from the skill repo, never invented:
#   * Discord's emoji cap is 256 KB, exact error [50138] ... 262144 bytes
#     (SKILL.md, "The size/format gate"). --target-kb multiplies by 1024, so
#     256 would sit exactly on the limit; 250 buys ~6 KB of honest margin
#     rather than betting on whether the platform compares with < or <=.
#   * "AVIF at 128x128, keeping every frame, trying q85 then q70" is the
#     measured cascade (SKILL.md "Decision procedure" step 3; all five test
#     assets fit that way). --avif-quality 85 --min-quality 70 reproduces
#     exactly that ladder and nothing wider.
#   * The q85 start is NOT decoration. --target-kb is a CEILING that never
#     spends unused headroom, so passing it alone delivers whatever the
#     default quality was -- measured at 99.8 KB / q70 with 150 KB of a 250 KB
#     cap unused. The top of the range has to be passed explicitly.
#
# Discord STICKERS are also 256 KB, but the repo records no dimension for them,
# so there is deliberately no `discord-sticker` preset inventing one --
# `under-256kb` covers that case and lets --target-kb's own ladder pick the
# largest resolution that fits.
# ---------------------------------------------------------------------------
PRESETS = {
    "full": {
        "flags": [],
        "blurb": "Best quality. Nothing shrunk, no frames dropped, original timing.",
    },
    "discord-emoji": {
        "flags": ["--format", "avif", "--resize-max-dim", "128",
                  "--avif-quality", "85", "--target-kb", "250", "--min-quality", "70"],
        "blurb": "Fits Discord's 256 KB emoji limit at 128x128, keeping every frame.",
    },
    "under-256kb": {
        "flags": ["--avif-quality", "85", "--target-kb", "250", "--min-quality", "70"],
        "blurb": "Any 256 KB cap (Discord stickers, Slack emoji) at the largest size that fits.",
    },
    "gif": {"flags": ["--format", "gif"], "blurb": "Force a .gif file, whatever the art wants."},
    "webp": {"flags": ["--format", "webp"], "blurb": "Force WebP (8-bit alpha, lossless)."},
    "avif": {"flags": ["--format", "avif"], "blurb": "Force AVIF (8-bit alpha, smallest)."},
    "apng": {"flags": ["--format", "apng"], "blurb": "Force APNG (8-bit alpha, lossless, largest)."},
}

# `--to under-900kb` and friends: a custom byte cap, parsed rather than enumerated.
_CUSTOM_CAP = re.compile(r"^under-(\d+)kb$", re.I)

# recommended_format's three possible values, mapped to an output extension.
# Read out of the script itself rather than guessed: 'gif-ok', 'webp-or-apng',
# 'webp-or-avif'. Both 8-bit verdicts start with webp, and SKILL.md's step 1
# ("full fidelity -> WebP lossless, the only bit-exact option") agrees.
FORMAT_EXT = {"gif-ok": "gif", "webp-or-apng": "webp", "webp-or-avif": "webp"}


def preset_flags(name):
    """Resolve a preset name to its flag list, or raise with a readable message."""
    if name in PRESETS:
        return list(PRESETS[name]["flags"])
    m = _CUSTOM_CAP.match(name)
    if m:
        kb = int(m.group(1))
        if kb < 1:
            raise ValueError("a size cap has to be at least 1 KB")
        return ["--avif-quality", "85", "--target-kb", str(kb), "--min-quality", "70"]
    raise ValueError(
        "unknown preset '%s'. Known: %s, or under-<N>kb for a custom cap."
        % (name, ", ".join(PRESETS)))


# ---------------------------------------------------------------------------
# Running the skill script
# ---------------------------------------------------------------------------
class Spinner:
    """A progress line for the long calls.

    --recommend measured 17.8s on a 177-frame 640x640 asset, and --auto pays it a
    SECOND time because it re-runs --recommend internally. Half a minute of dead
    terminal reads as a hang, so the wait is narrated rather than hidden.
    """

    FRAMES = "|/-\\"

    def __init__(self, label):
        self.label = label
        self._stop = threading.Event()
        self._t = None

    def __enter__(self):
        if sys.stderr.isatty():
            self._t = threading.Thread(target=self._run, daemon=True)
            self._t.start()
        else:
            err("  %s..." % self.label)
        return self

    def _run(self):
        i = 0
        start = time.time()
        while not self._stop.is_set():
            print("\r  %s%s%s %s %s(%ds)%s " % (
                CMD, self.FRAMES[i % 4], RESET, self.label, DIM, int(time.time() - start), RESET),
                end="", file=sys.stderr, flush=True)
            i += 1
            self._stop.wait(0.12)

    def __exit__(self, *exc):
        self._stop.set()
        if self._t:
            self._t.join(timeout=1)
            print("\r" + " " * (len(self.label) + 24) + "\r", end="", file=sys.stderr, flush=True)
        return False


def skill_script():
    """Locate the skill's script.

    Prefers the dev repo (so `dior gif` dogfoods the working tree, mirroring how
    DIOR_BOT_DIR already points at the bot repo), and falls back to the bundle
    claude.ai syncs onto this machine. Which one was used is always printed --
    a silent fallback would make the CLI and the live skill disagree invisibly.
    """
    env = os.environ.get("DIOR_GIF_SCRIPT")
    if env and Path(env).is_file():
        return Path(env), "repo"
    repo = os.environ.get("DIOR_GIF_DIR", "/Applications/Claude Code/Gif-Background-Remover")
    p = Path(repo) / "scripts" / "remove_gif_background.py"
    if p.is_file():
        return p, "repo"
    base = Path.home() / "Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin"
    hits = sorted(base.glob("*/*/skills/gif-background-remover/scripts/remove_gif_background.py"))
    if hits:
        return hits[-1], "synced"
    raise SystemExit(
        "%s⚠️  Couldn't find the gif-background-remover script.%s\n"
        "   Looked in %s and the synced claude.ai bundle.\n"
        "   Set DIOR_GIF_DIR in ~/.config/dior/core.zsh to the repo that holds it."
        % (ERROR, RESET, repo))


def run_skill(script, args, capture_json=False, label=None):
    """Invoke the skill script. Returns (returncode, stdout, stderr)."""
    cmd = [sys.executable, str(script)] + args
    if capture_json:
        with Spinner(label or "working"):
            p = subprocess.run(cmd, capture_output=True, text=True)
        return p.returncode, p.stdout, p.stderr
    # Rendering streams its own progress to stderr; let it through untouched.
    p = subprocess.run(cmd, stdout=subprocess.PIPE, text=True)
    return p.returncode, p.stdout, ""


# The phases --auto announces on stderr, mapped to something worth reading. Matched
# by the "n/3" marker rather than the words after it, so a reworded banner degrades
# to the generic label instead of losing the progress line entirely.
_AUTO_PHASES = {
    "1/3": "reading the picture",
    "2/3": "making it",
    "3/3": "checking its own work",
}


def render(script, args):
    """Run --auto, showing a phase, and return (rc, full stderr log).

    The raw stream is CAPTURED rather than passed through, and that is the point of
    this function. --auto narrates itself to an agent: nine lines of "evidence: A
    SOLID art colour sits 57 from the background, inside the default feather band
    (15..60)" is correct, useful output for the thing it was written for, and is
    exactly what this CLI exists to stand in front of. The log is kept in full and
    printed verbatim when the run FAILS, because at that point the jargon is the
    only thing that can explain why.
    """
    cmd = [sys.executable, str(script)] + args
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    log, phase, decided = [], "starting", None
    tty = sys.stderr.isatty()
    start = time.time()
    for line in p.stderr:
        log.append(line.rstrip("\n"))
        for marker, label in _AUTO_PHASES.items():
            if marker in line and "AUTO" in line:
                phase = label
        if line.startswith("  applying:"):
            decided = line.split(":", 1)[1].strip()
        if tty:
            print("\r  %s%s%s %s(%ds)%s%s" % (CMD, phase, RESET, DIM,
                                              int(time.time() - start), RESET, " " * 20),
                  end="", file=sys.stderr, flush=True)
    p.wait()
    if tty:
        print("\r" + " " * 60 + "\r", end="", file=sys.stderr, flush=True)
    return p.returncode, log, decided


def recommend(script, path):
    rc, so, se = run_skill(script, [str(path), "--recommend"], capture_json=True,
                           label="analysing %s" % Path(path).name)
    if rc != 0 or not so.strip():
        err("%s⚠️  Analysis failed for %s%s" % (ERROR, path, RESET))
        if se.strip():
            err(DIM + se.strip()[-1500:] + RESET)
        return None
    try:
        data = json.loads(so)
    except json.JSONDecodeError:
        err("%s⚠️  Analysis returned something that wasn't JSON for %s%s" % (ERROR, path, RESET))
        return None
    # Several paths return a one-entry list (the multi-input shape).
    if isinstance(data, list):
        data = data[0].get("recommendation", data[0]) if data else None
    return data


# ---------------------------------------------------------------------------
# Showing the human what the question is about
# ---------------------------------------------------------------------------
def _frames(path, indices):
    """Load the requested frame indices as RGB images, skipping any that don't exist."""
    from PIL import Image, ImageSequence
    imgs = []
    with Image.open(path) as im:
        wanted = set(indices)
        for i, fr in enumerate(ImageSequence.Iterator(im)):
            if i in wanted:
                imgs.append((i, fr.convert("RGBA")))
            if len(imgs) == len(wanted):
                break
    return imgs


def _checkerboard(size, cell=8):
    """A checkerboard to composite over, so transparency reads as transparency."""
    from PIL import Image
    w, h = size
    bg = Image.new("RGBA", (w, h), (255, 255, 255, 255))
    px = bg.load()
    for y in range(h):
        for x in range(w):
            if ((x // cell) + (y // cell)) % 2:
                px[x, y] = (208, 208, 208, 255)
    return bg


def show_region(path, bbox, tmpdir, label, open_it=True):
    """Write a PNG showing the disputed region across three sampled frames, and open it.

    Three frames rather than one, deliberately: the whole reason the region is a
    coin flip is that its enclosure CHANGES across the animation, so a single
    still is the one view guaranteed not to show what the question is about.
    """
    from PIL import Image, ImageDraw
    try:
        with Image.open(path) as probe:
            n = getattr(probe, "n_frames", 1)
        picks = sorted({0, n // 2, max(0, n - 1)})
        frames = _frames(path, picks)
        if not frames:
            return None
        x0, y0, x1, y1 = [int(v) for v in bbox]
        pad = max(24, (x1 - x0) // 2, (y1 - y0) // 2)
        W, H = frames[0][1].size
        cx0, cy0 = max(0, x0 - pad), max(0, y0 - pad)
        cx1, cy1 = min(W, x1 + pad), min(H, y1 + pad)
        if cx1 <= cx0 or cy1 <= cy0:
            return None

        tiles = []
        for _, fr in frames:
            board = _checkerboard(fr.size)
            comp = Image.alpha_composite(board, fr)
            d = ImageDraw.Draw(comp)
            d.rectangle([x0, y0, x1, y1], outline=(255, 0, 128, 255), width=3)
            tile = comp.crop((cx0, cy0, cx1, cy1))
            scale = max(1, min(6, 420 // max(1, tile.width)))
            if scale > 1:
                tile = tile.resize((tile.width * scale, tile.height * scale), Image.NEAREST)
            tiles.append(tile)

        gap = 16
        sheet = Image.new("RGB",
                          (sum(t.width for t in tiles) + gap * (len(tiles) - 1),
                           max(t.height for t in tiles)),
                          (24, 24, 28))
        x = 0
        for t in tiles:
            sheet.paste(t.convert("RGB"), (x, 0))
            x += t.width + gap
        dest = Path(tmpdir) / ("%s.png" % label)
        sheet.save(dest)
        if open_it:
            _open(dest)
        return dest
    except Exception as e:                                   # noqa: BLE001
        err("%s   (couldn't render a preview of that region: %s)%s" % (DIM, e, RESET))
        return None


def show_frame(path, index, tmpdir, label, open_it=True):
    """Write and open one whole frame — used for the fade question.

    Whole frame, not a crop: a fade is diffuse by definition, so cropping to a
    bbox would remove the thing being asked about.
    """
    from PIL import Image
    try:
        frames = _frames(path, [index])
        if not frames:
            return None
        fr = frames[0][1]
        comp = Image.alpha_composite(_checkerboard(fr.size), fr).convert("RGB")
        scale = max(1, min(4, 640 // max(1, comp.width)))
        if scale > 1:
            comp = comp.resize((comp.width * scale, comp.height * scale), Image.NEAREST)
        dest = Path(tmpdir) / ("%s.png" % label)
        comp.save(dest)
        if open_it:
            _open(dest)
        return dest
    except Exception as e:                                   # noqa: BLE001
        err("%s   (couldn't render that frame: %s)%s" % (DIM, e, RESET))
        return None


def _open(p):
    if sys.platform == "darwin" and shutil.which("open"):
        subprocess.run(["open", str(p)], check=False)


# ---------------------------------------------------------------------------
# Asking
# ---------------------------------------------------------------------------
def ask(question, options, default_index=0):
    """A numbered menu. Returns the chosen option's key.

    `options` is a list of (key, label, detail).
    """
    out("")
    out("%s%s%s" % (HEAD, question, RESET))
    for i, (_k, label, detail) in enumerate(options, 1):
        marker = "%s%d%s" % (CMD, i, RESET)
        suffix = "  %s%s%s" % (DIM, detail, RESET) if detail else ""
        out("  %s) %s%s" % (marker, label, suffix))
    d = options[default_index][1]
    while True:
        try:
            raw = input("  %s> %s[1-%d, Enter = %s]%s " % (CMD, DIM, len(options), d, RESET)).strip()
        except (EOFError, KeyboardInterrupt):
            out("")
            raise SystemExit("%sCancelled — nothing was written.%s" % (WARN, RESET))
        if raw == "":
            return options[default_index][0]
        if raw.isdigit() and 1 <= int(raw) <= len(options):
            return options[int(raw) - 1][0]
        out("  %sPick a number between 1 and %d.%s" % (WARN, len(options), RESET))


# ---------------------------------------------------------------------------
# Plain-English reporting of what the analysis found
# ---------------------------------------------------------------------------
def describe(rec, name):
    a = rec.get("analysis") or {}
    fmt = rec.get("recommended_format")
    out("")
    out("%s%s%s" % (TITLE, name, RESET))
    bg = a.get("detected_bg_color")
    frames = a.get("n_frames_total")
    if bg:
        out("  %sBackground%s   #%s%s" % (DIM, RESET, bg,
                                          "  %s(%s frames)%s" % (DIM, frames, RESET) if frames else ""))
    hard = ((a.get("edge_hardness") or {}).get("appears_hard_edged"))
    if hard:
        out("  %sEdges%s        hard-edged — looks like pixel art, so it'll be cut without softening"
            % (DIM, RESET))
    elif hard is False:
        out("  %sEdges%s        antialiased — edges get feathered so they don't look jagged" % (DIM, RESET))
    if fmt == "gif-ok":
        out("  %sBest format%s  GIF is fine for this art" % (DIM, RESET))
    elif fmt:
        out("  %sBest format%s  needs real transparency levels, so WebP rather than GIF %s(%s)%s"
            % (DIM, RESET, DIM, fmt, RESET))
    if a.get("has_fully_transparent_frame"):
        out("  %s⚠️  One or more frames end up fully transparent — a GIF truncates there, so this "
            "one can't ship as a GIF%s" % (WARN, RESET))
    if a.get("source_has_pre_existing_transparency"):
        out("  %sNote%s         this file already has some transparency; it's carried through" % (DIM, RESET))


def show_evidence(rec):
    ev = rec.get("evidence") or []
    if not ev:
        return
    out("  %sWhy:%s" % (DIM, RESET))
    for line in ev:
        first = str(line).strip().split(". ")[0]
        out("    %s· %s%s" % (DIM, first[:160], RESET))


# ---------------------------------------------------------------------------
# The interview
# ---------------------------------------------------------------------------
def answer_questions(rec, path, tmpdir, assume, open_previews):
    """Turn --recommend's structured doubts into flags. Returns a flag list, or None to skip."""
    flags = []

    amb = rec.get("ambiguous_protection") or []
    protect, remove = [], []
    for i, region in enumerate(amb):
        color = region.get("outline_color")
        bbox = region.get("bbox_xyxy") or [0, 0, 0, 0]
        ratio = region.get("enclosure_ratio")
        got = region.get("frames_enclosed")
        tot = region.get("frames_checked")
        if assume:
            (protect if assume == "protect" else remove).append(color)
            continue
        out("")
        out("  %sThere's a hole in the artwork and I can't tell what it is.%s" % (WARN, RESET))
        out("  %sIt's sealed off by a #%s outline on %s of %s frames%s%s"
            % (DIM, color, got, tot,
               (" (%.0f%%)" % (ratio * 100)) if isinstance(ratio, (int, float)) else "", RESET))
        shown = show_region(path, bbox, tmpdir, "region-%d" % i, open_it=open_previews)
        if shown and open_previews:
            out("  %sOpened a picture of it — the pink box is the area in question.%s" % (DIM, RESET))
        elif shown:
            out("  %sPicture: %s%s" % (DIM, shown, RESET))
        choice = ask(
            "Should the area inside the pink box be see-through, or stay filled in?",
            [("protect", "Stay filled in", "it's part of the picture — a highlight, an eye, a label"),
             ("remove", "Make it see-through", "it's just background showing through a gap")],
            default_index=0)
        (protect if choice == "protect" else remove).append(color)

    if protect:
        flags += ["--assume-protect", ",".join(dict.fromkeys(protect))]
    if remove:
        flags += ["--assume-remove", ",".join(dict.fromkeys(remove))]

    fade = rec.get("nameable_fade")
    if fade:
        if assume:
            flags += ["--assume-no-fade"] if assume == "remove" else \
                     ["--recover-fade-alpha", "--fade-color", fade["color"]]
        else:
            out("")
            out("  %sThis picture fades out softly somewhere, and I can't tell if that's on purpose.%s"
                % (WARN, RESET))
            out("  %s%s pixels on frame %s fade toward the background.%s"
                % (DIM, fade.get("faint_px"), fade.get("frame_index"), RESET))
            shown = show_frame(path, int(fade.get("frame_index") or 0), tmpdir, "fade",
                               open_it=open_previews)
            if shown and open_previews:
                out("  %sOpened that frame so you can look at it.%s" % (DIM, RESET))
            elif shown:
                out("  %sPicture: %s%s" % (DIM, shown, RESET))
            choice = ask(
                "Is that soft glow / sparkle trail part of the picture?",
                [("keep", "Yes, keep the glow",
                  "saved as WebP so the fade survives — a GIF can't hold it"),
                 ("drop", "No, cut it off cleanly", "treat the falloff as background")],
                default_index=0)
            if choice == "keep":
                flags += ["--recover-fade-alpha", "--fade-color", fade["color"]]
            else:
                flags += ["--assume-no-fade"]
    return flags


def ask_goal():
    keys = ["full", "discord-emoji", "under-256kb", "gif"]
    choice = ask(
        "What's this for?",
        [(k, k.replace("-", " ").capitalize() if k != "full" else "Best quality",
          PRESETS[k]["blurb"]) for k in keys] +
        [("custom", "A specific size cap", "you'll be asked for a number in KB")],
        default_index=0)
    if choice != "custom":
        return choice
    while True:
        try:
            raw = input("  %s> %ssize cap in KB, e.g. 500%s " % (CMD, DIM, RESET)).strip()
        except (EOFError, KeyboardInterrupt):
            raise SystemExit("%sCancelled — nothing was written.%s" % (WARN, RESET))
        if raw.isdigit() and int(raw) > 0:
            return "under-%dkb" % int(raw)
        out("  %sA whole number of kilobytes, please.%s" % (WARN, RESET))


# ---------------------------------------------------------------------------
# Output naming — never overwrite something already delivered
# ---------------------------------------------------------------------------
def output_path(src, ext, out_dir):
    """<stem>_transparent.<ext>, escalating to _v2/_v3 rather than overwriting.

    This is the skill's own delivery convention (SKILL.md, "Delivery file naming"),
    and it is also the safe one: an earlier delivery is a thing someone may already
    have used.
    """
    src = Path(src)
    d = Path(out_dir) if out_dir else src.parent
    d.mkdir(parents=True, exist_ok=True)
    cand = d / ("%s_transparent.%s" % (src.stem, ext))
    n = 2
    while cand.exists():
        cand = d / ("%s_transparent_v%d.%s" % (src.stem, n, ext))
        n += 1
    return cand


def human_size(n):
    return "%.1f KB" % (n / 1024) if n < 1024 * 1024 else "%.2f MB" % (n / 1024 / 1024)


# ---------------------------------------------------------------------------
# Verification, reported honestly
# ---------------------------------------------------------------------------
def verify(script, src, dst, answers):
    """Re-check the written file.

    ⚠️ The --assume-remove answers have to be passed through. verify() takes
    `assume_remove_colors` and uses it to drop the regions the run was TOLD to
    remove; without it, an interior the person explicitly asked to be see-through
    comes back as `looks_unprotected: true` and reads as a defect. Measured on the
    megaphone asset: two of its three regions report exactly that.

    This is a second full pass over every frame and it is not free -- around 30s on
    a 144-frame 640x640 file, on top of the identical pass --auto already ran
    internally and printed as prose. Paying it buys a STRUCTURED verdict rather
    than a parsed one, which is the only kind worth printing a tick next to.
    Filed as a real duplication in the skill repo's own backlog.
    """
    extra = []
    if "--assume-remove" in answers:
        extra = ["--assume-remove", answers[answers.index("--assume-remove") + 1]]
    rc, so, se = run_skill(script, [str(src), str(dst), "--verify"] + extra, capture_json=True,
                           label="checking every frame")
    if rc != 0 or not so.strip():
        return None
    try:
        v = json.loads(so)
    except json.JSONDecodeError:
        return None
    return v[0] if isinstance(v, list) and v else v


def report_verify(v):
    """Say what was actually checked, and only that.

    ⚠️ REWRITTEN 2026-09-03 15:58 EDT AFTER EVERY CHECK IN THE FIRST VERSION WAS DEAD.
    It read three fields at the wrong type -- `leftover_background_opaque_px` is a
    dict (`max_per_frame`), not a number; `protected_region_coverage` is a LIST of
    per-region dicts, not one dict; `timing` is a STRING, not a dict -- so all three
    `isinstance` guards fell through and the function printed "background gone
    everywhere, protected parts intact, no pale fringe, timing unchanged" without
    having looked at any of it. On the very asset it was first run against, the JSON
    said two regions were unprotected. A check that cannot fail is worse than no
    check, because it manufactures confidence; this is the failure class the comment
    in the previous version was warning about, committed by that same version.

    Everything below is now read from a real key of the shape --verify actually
    returns, and anything absent is reported as NOT CHECKED rather than as passing.
    """
    if not v:
        out("  %sCouldn't run the automatic check on this one.%s" % (WARN, RESET))
        return

    # --verify skips EVERY pixel check when the output was cropped or resized, and
    # names them here. A tick in that case is a vacuous pass.
    skipped = v.get("checks_skipped") or []
    if not skipped and v.get("dimensions_match") is False:
        skipped = ["the output is a different size from the source"]

    problems = []
    lb = v.get("leftover_background_opaque_px")
    left = lb.get("max_per_frame") if isinstance(lb, dict) else None
    if isinstance(left, (int, float)) and left > 0:
        problems.append("%d background pixels are still solid on the worst frame"
                        % int(left))

    # Pre-filtered by the tool, and already excludes anything --assume-remove named.
    unprotected = v.get("unprotected_design_regions")
    if unprotected is None:
        unprotected = [r for r in (v.get("protected_region_coverage") or [])
                       if isinstance(r, dict) and r.get("looks_unprotected")]
    if unprotected:
        problems.append("%d part%s meant to stay filled in came out see-through"
                        % (len(unprotected), "" if len(unprotected) == 1 else "s"))

    fr = v.get("edge_fringe_check")
    if isinstance(fr, dict) and fr.get("looks_fringed"):
        problems.append("the outline has a pale fringe on it")

    infl = v.get("small_region_inflation")
    if isinstance(infl, dict) and (infl.get("flagged_count") or 0) > 0:
        problems.append("%d small detail%s got eaten and came out bigger than %s should"
                        % (infl["flagged_count"],
                           *(("", "it") if infl["flagged_count"] == 1 else ("s", "they"))))

    if v.get("opaque_survival_warning"):
        problems.append(str(v["opaque_survival_warning"])[:140])
    if v.get("output_is_empty"):
        problems.append(str(v["output_is_empty"])[:140])

    # ⚠️ A LOWER OUTPUT FRAME COUNT IS NOT A DEFECT, and treating it as one was a real
    # false positive here: a 177-frame source came back as "89 frames written from 177
    # intended -- 88 identical frame(s) coalesced by the encoder, TOTAL PLAYBACK
    # UNCHANGED at 3600ms" and was reported to the user as "playback timing changed".
    # Pillow coalesces consecutive frames that are byte-identical after quantization and
    # folds their delays into the survivor; SKILL.md says so explicitly, and describe_
    # written_timing already distinguishes the two cases in its own wording. So this
    # reads that verdict instead of string-matching one happy phrase.
    #
    # The unknown case is deliberately treated as a PROBLEM rather than a pass: a
    # rewording upstream should make this shout, not go quiet.
    timing = v.get("timing")
    if isinstance(timing, str):
        benign = ("durations preserved exactly" in timing
                  or "total playback unchanged" in timing)
        if "real timing defect" in timing or not benign:
            problems.append("playback timing changed — %s" % timing[:120])

    # ⚠️ Do NOT collapse this into v["verified"]. Measured on a resized output: verified
    # is False purely because the pixel checks were SKIPPED, with nothing wrong in the
    # file. A scope statement reported as a failure is as misleading as the reverse.
    if problems:
        out("  %sChecked, and found problems:%s" % (WARN, RESET))
        for pr in problems:
            out("    %s· %s%s" % (WARN, pr, RESET))
    elif skipped:
        out("  %sChecked:%s frame count and timing only." % (DIM, RESET))
    else:
        bits = ["background gone everywhere"]
        if v.get("protected_region_coverage"):
            bits.append("the parts you kept are intact")
        bits.append("no pale fringe")
        if isinstance(timing, str):
            bits.append("timing unchanged")
        out("  %sChecked:%s %s." % (OK, RESET, ", ".join(bits)))

    if skipped:
        out("  %s⚠️  The picture-by-picture checks did NOT run%s %s(%s)%s%s — this is not a "
            "clean bill of health, so look at the result yourself.%s"
            % (WARN, RESET, DIM, "; ".join(str(x)[:200] for x in skipped), RESET, WARN, RESET))


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
def cmd_check(args):
    script, origin = skill_script()
    if origin == "synced":
        out("%sUsing the synced claude.ai copy of the skill (the dev repo wasn't found).%s"
            % (DIM, RESET))
    for path in args.files:
        rec = recommend(script, path)
        if rec is None:
            continue
        describe(rec, Path(path).name)
        na = rec.get("not_applicable_reason")
        if na:
            out("  %s⚠️  %s%s" % (WARN, na, RESET))
        amb = rec.get("ambiguous_protection") or []
        if amb:
            out("  %sWill ask you about%s %d spot%s it can't classify on its own"
                % (DIM, RESET, len(amb), "" if len(amb) == 1 else "s"))
        if rec.get("nameable_fade"):
            out("  %sWill ask you about%s a soft fade it can't classify on its own" % (DIM, RESET))
        if not amb and not rec.get("nameable_fade") and not na:
            out("  %sNo questions — this one can be done straight through.%s" % (OK, RESET))
        if args.why:
            show_evidence(rec)
    return 0


def cmd_clean(args):
    script, origin = skill_script()
    if origin == "synced":
        out("%sUsing the synced claude.ai copy of the skill (the dev repo wasn't found).%s"
            % (DIM, RESET))

    try:
        goal_flags = preset_flags(args.to) if args.to else None
    except ValueError as e:
        err("%s⚠️  %s%s" % (ERROR, e, RESET))
        return 1

    interactive = not args.yes and sys.stdin.isatty()
    tmpdir = tempfile.mkdtemp(prefix="dior-gif-")
    results, failures = [], []

    for path in args.files:
        src = Path(path)
        if not src.is_file():
            err("%s⚠️  No such file: %s%s" % (ERROR, path, RESET))
            failures.append((path, "not found"))
            continue

        rec = recommend(script, src)
        if rec is None:
            failures.append((path, "analysis failed"))
            continue
        describe(rec, src.name)

        na = rec.get("not_applicable_reason")
        if na:
            out("  %s⚠️  %s%s" % (WARN, na, RESET))
            if not interactive:
                failures.append((path, "the tool says it can't handle this one"))
                continue
            if ask("Try anyway?",
                   [("no", "Skip this file", "recommended — the tool has a reason"),
                    ("yes", "Do it anyway", "the result may be wrong")],
                   default_index=0) == "no":
                failures.append((path, "skipped — " + str(na)[:80]))
                continue

        # The questions. Under --yes nothing is asked, and every assumption is
        # printed, because an assumption that leaves no trace is indistinguishable
        # from a measurement.
        assume = "protect" if args.yes else None
        answers = answer_questions(rec, src, tmpdir, assume, not args.no_preview)
        if args.yes and answers:
            out("  %sAssumed:%s kept every uncertain area filled in %s(--yes)%s"
                % (WARN, RESET, DIM, RESET))

        # The goal. Asked, never inferred — a guessed size target is the skill's
        # own #1 measured failure mode, and it is invisible downstream.
        this_goal = args.to
        if goal_flags is None:
            this_goal = ask_goal() if interactive else "full"
        flags = preset_flags(this_goal)

        ext = FORMAT_EXT.get(rec.get("recommended_format"), "gif")
        if "--format" in flags:
            forced = flags[flags.index("--format") + 1]
            ext = "png" if forced == "apng" else forced
        dst = output_path(src, ext, args.out)

        preview = None
        if not args.no_preview:
            preview = Path(tmpdir) / ("%s-preview.png" % src.stem)
            flags += ["--preview", str(preview)]

        cmd = [str(src), str(dst), "--auto"] + answers + flags
        out("")
        rc, log, decided = render(script, cmd)
        if rc != 0 or not dst.exists():
            err("  %s⚠️  That one didn't work.%s" % (ERROR, RESET))
            # The jargon is unreadable right up until it is the only thing that
            # explains the failure, so it is withheld on success and shown on error.
            for line in log[-25:]:
                err("    %s%s%s" % (DIM, line, RESET))
            failures.append((path, "render failed"))
            continue

        if decided:
            out("  %sWorked out on its own:%s %s%s%s" % (DIM, RESET, DIM, decided, RESET))
        size = dst.stat().st_size
        out("  %sDone:%s %s %s(%s)%s" % (OK, RESET, dst, DIM, human_size(size), RESET))
        report_verify(verify(script, src, dst, answers))
        if preview and preview.exists() and not args.no_preview:
            _open(preview)
            out("  %sOpened a strip of frames on a checkerboard so you can see the transparency.%s"
                % (DIM, RESET))
        results.append((dst, size, this_goal))

    # The OFFER, not the act. SKILL.md's size gate case 1: name the size and offer,
    # then wait. Never infer a target from the file merely being large.
    big = [(d, s) for d, s, g in results if g == "full" and s > 256 * 1024]
    if big:
        out("")
        for d, s in big:
            out("  %s%s came out at %s.%s" % (DIM, d.name, human_size(s), RESET))
        out("  %sIf that needs to be smaller for somewhere specific, re-run with"
            " %s--to discord-emoji%s or %s--to under-256kb%s.%s"
            % (HELP, OPT, HELP, OPT, HELP, RESET))

    if failures:
        out("")
        out("  %sDidn't finish:%s" % (WARN, RESET))
        for p, why in failures:
            out("    %s· %s — %s%s" % (DIM, Path(p).name, why, RESET))
    return 1 if failures and not results else 0


def cmd_presets(_args):
    out("%sWhat you can ask for%s %s— dior gif clean <file> --to <one of these>%s"
        % (TITLE, RESET, DIM, RESET))
    out("")
    width = max(len(k) for k in PRESETS)
    for k, v in PRESETS.items():
        out("  %s%-*s%s  %s%s%s" % (OPT, width, k, RESET, DIM, v["blurb"], RESET))
    out("  %s%-*s%s  %sAny cap you name, e.g. under-500kb.%s" % (OPT, width, "under-<N>kb", RESET, DIM, RESET))
    out("")
    out("  %sLeave --to off and you'll be asked. The default is best quality —%s" % (HELP, RESET))
    out("  %snothing is ever shrunk unless you say so.%s" % (HELP, RESET))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(prog="dior gif", add_help=False)
    sub = p.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("check", add_help=False)
    c.add_argument("files", nargs="+")
    c.add_argument("--why", action="store_true")
    c.set_defaults(fn=cmd_check)

    k = sub.add_parser("clean", add_help=False)
    k.add_argument("files", nargs="+")
    k.add_argument("--to", default=None)
    k.add_argument("--out", default=None)
    k.add_argument("--yes", action="store_true")
    k.add_argument("--no-preview", action="store_true")
    k.set_defaults(fn=cmd_clean)

    s = sub.add_parser("presets", add_help=False)
    s.set_defaults(fn=cmd_presets)

    args = p.parse_args(argv)
    try:
        return args.fn(args)
    except KeyboardInterrupt:
        out("")
        out("%sStopped. Nothing was written.%s" % (WARN, RESET))
        return 130


if __name__ == "__main__":
    sys.exit(main())

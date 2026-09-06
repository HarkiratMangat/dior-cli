#!/usr/bin/env node
"use strict";
/**
 * reflow-prose.mjs — convert hard-wrapped Markdown prose to soft-wrapped
 * (one logical line per paragraph / list item / quoted paragraph).
 *
 * Ported from Diors-Builds' `scripts/reflow-prose.mjs` (2026-08-08, drastically
 * revised 2026-08-14/08-20) — this replaces the older `unwrap-hard-breaks.js`
 * that `dior text unwrap` used to shell out to. The older tool's blockquote
 * handling collapsed a multi-paragraph `>` block into a single marker line,
 * losing the bare `>` that marks a paragraph BREAK inside a quote — measured
 * against Diors-Builds' own docs, it merged distinct quoted paragraphs and
 * dropped dozens of `>` markers. This version reflows a blockquote's inner
 * content THROUGH THE SAME FUNCTION (stripping the marker, recursing, then
 * restoring it per output line), so nesting and blank separators inside
 * quotes work by construction instead of by special case.
 *
 * THE INVARIANT: reflowing may only ever DELETE newlines and leading
 * indentation. It must never add, drop, or reorder a non-whitespace
 * character — tokens(before) === tokens(after). verify() asserts that, plus
 * structural counts a token stream alone can't prove (headings, table rows,
 * HTML/comment lines, quote paragraph breaks, list markers, fence balance,
 * fenced-block content).
 *
 * NOT ported: Diors-Builds' independent CommonMark (markdown-it) oracle —
 * this repo carries no npm dependencies, and the invariants above are the
 * same ones that originally caught the older tool's bugs.
 *
 * Usage:
 *   node reflow-prose.mjs <input-file>|- <output-file>
 *   (input "-" reads stdin, for pasted text with no file on disk)
 *
 * Prints "inputLines outputLines changed" on success (changed is 0 or 1),
 * matching unwrap-hard-breaks.js's machine-readable line so callers don't
 * need to change. On a verify() failure, nothing is written to outputPath;
 * problems are printed to stderr and the process exits 1.
 */

import fs from "node:fs";

/* ─────────────────────────── line classification ────────────────────────── */

const isFence = (l) => l.match(/^\s*(```+|~~~+)/);
const isHeading = (l) => /^\s{0,3}#{1,6}(\s|$)/.test(l);
const isHR = (l) => /^\s{0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$/.test(l);
const isTableRow = (l) =>
  /^\s*\|.*\|\s*$/.test(l) || /^\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)+$/.test(l);

// Raw-HTML lines must not be folded into prose, but "starts with `<`" tears
// ordinary sentences apart (e.g. "`git show\n  <sha>:package.json`"). So:
// comments are always block-level, and any other angle-bracket line counts
// only when the tag is an actual HTML element.
const HTML_TAGS = new Set([
  "a", "abbr", "b", "blockquote", "br", "code", "dd", "details", "div", "dl",
  "dt", "em", "figcaption", "figure", "h1", "h2", "h3", "h4", "h5", "h6", "hr",
  "i", "img", "kbd", "li", "ol", "p", "picture", "pre", "s", "samp", "section",
  "small", "span", "strong", "sub", "summary", "sup", "table", "tbody", "td",
  "tfoot", "th", "thead", "tr", "u", "ul", "video",
]);
function isHtml(l) {
  if (/^\s*<!--/.test(l)) return true;
  const m = l.match(/^\s*<\/?([a-zA-Z][a-zA-Z0-9-]*)/);
  return !!m && HTML_TAGS.has(m[1].toLowerCase());
}
const listMarker = (l) => l.match(/^(\s*)([-*+]|\d{1,9}[.)])(\s+)/);

// A line opening with `**Label:**` always starts a new logical line — never
// absorbed as a continuation. Otherwise consecutive metadata fields (e.g. a
// legal doc's "**Effective date:** …" / "**Version:** …" block) fold into one.
const isFieldLine = (l) => /^\s*\*\*[^*\n]+:\*\*/.test(l);

// A genuine Markdown hard break: two+ trailing spaces, or an odd run of
// trailing backslashes. Re-emitted rather than silently dropped.
function hardBreak(raw) {
  if (/ {2,}$/.test(raw)) return "  ";
  const t = raw.replace(/[ \t]+$/, "");
  const run = t.match(/\\+$/);
  if (run && run[0].length % 2 === 1) return "";
  return null;
}

/* ──────────────────────────────── the reflow ────────────────────────────── */

export function reflow(text) {
  const lines = text.split("\n");
  const out = [];

  // Front matter is data, not prose — passed through untouched.
  let i = 0;
  if (lines[0] !== undefined && lines[0].trim() === "---") {
    out.push(lines[0]);
    i = 1;
    while (i < lines.length) {
      out.push(lines[i]);
      const closed = lines[i].trim() === "---";
      i++;
      if (closed) break;
    }
  }

  let para = null; // { prefix, parts, isList, trail }
  const flush = () => {
    if (para) {
      out.push(para.prefix + para.parts.join(" ") + (para.trail || ""));
      para = null;
    }
  };

  for (; i < lines.length; i++) {
    const raw = lines[i];

    const fence = isFence(raw);
    if (fence) {
      flush();
      out.push(raw);
      const char = fence[1][0];
      i++;
      for (; i < lines.length; i++) {
        out.push(lines[i]);
        if (lines[i].trim().startsWith(char.repeat(3))) break;
      }
      continue;
    }

    // Blockquote: strip marker, reflow the inside recursively, restore marker.
    const bq = raw.match(/^(\s*>[ \t]?)/);
    if (bq) {
      flush();
      const body = [];
      const marker = raw.match(/^\s*>/)[0] + " ";
      for (; i < lines.length; i++) {
        const m = lines[i].match(/^(\s*>[ \t]?)(.*)$/);
        if (!m) break;
        body.push(m[2]);
      }
      i--;
      for (const l of reflow(body.join("\n")).split("\n")) {
        // A blank line inside a quote is a bare `>` — a paragraph separator.
        out.push(l.trim() === "" ? marker.trimEnd() : marker + l);
      }
      continue;
    }

    if (raw.trim() === "") {
      flush();
      out.push(raw);
      continue;
    }

    if (isHeading(raw) || isHR(raw) || isTableRow(raw) || isHtml(raw)) {
      flush();
      out.push(raw);
      continue;
    }

    const indent = raw.match(/^[ \t]*/)[0].length;

    // Indented code block (4+ spaces, and not a continuation of a list item).
    if (!para && indent >= 4) {
      out.push(raw);
      continue;
    }

    const marker = listMarker(raw);
    if (marker) {
      flush();
      const head = marker[1].length + marker[2].length + marker[3].length;
      para = { prefix: raw.slice(0, head), parts: [raw.slice(head).trim()], isList: true };
      const hb = hardBreak(raw);
      if (hb !== null) {
        para.trail = hb;
        flush();
      }
      continue;
    }

    // A field line always opens a new logical line, never a continuation.
    if (isFieldLine(raw)) {
      flush();
      para = { prefix: raw.match(/^[ \t]*/)[0], parts: [raw.trim()] };
      const hb = hardBreak(raw);
      if (hb !== null) {
        para.trail = hb;
        flush();
      }
      continue;
    }

    // Continuation of the current paragraph or list item. A list item only
    // absorbs an INDENTED (>=2) continuation — an unindented line after a
    // list item is a lazy continuation whose block boundary is worth keeping
    // visible; under-joining here is fixable later, over-joining is not.
    if (para) {
      if (para.isList && indent < 2) {
        flush();
      } else {
        para.parts.push(raw.trim());
        const hb = hardBreak(raw);
        if (hb !== null) {
          para.trail = hb;
          flush();
        }
        continue;
      }
    }

    para = { prefix: raw.match(/^[ \t]*/)[0], parts: [raw.trim()] };
    const hb = hardBreak(raw);
    if (hb !== null) {
      para.trail = hb;
      flush();
    }
  }

  flush();
  return out.join("\n");
}

/* ───────────────────────────── the verifier ─────────────────────────────── */

// Blockquote markers are STRUCTURE, not content — joining four quoted lines
// into one legitimately turns four `>` into one, so they're stripped here
// and asserted separately below (isQuoteBreak).
const tokens = (s) =>
  s
    .split("\n")
    .map((l) => l.replace(/^\s*(?:>[ \t]?)+/, ""))
    .join("\n")
    .split(/\s+/)
    .filter(Boolean);

const countOf = (s, pred) => s.split("\n").filter(pred).length;

// A bare `>` is a paragraph BREAK inside a quote — losing one merges two
// distinct quoted paragraphs, the exact corruption the older tool caused.
const isQuoteBreak = (l) => /^\s*>[ \t]*$/.test(l);

// Fenced-block contents must survive byte-identically, compared whole.
function fences(s) {
  const res = [];
  const lines = s.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const f = isFence(lines[i]);
    if (!f) continue;
    const char = f[1][0];
    const buf = [lines[i]];
    for (i++; i < lines.length; i++) {
      buf.push(lines[i]);
      if (lines[i].trim().startsWith(char.repeat(3))) break;
    }
    res.push(buf.join("\n"));
  }
  return res;
}

// An odd number of fence lines means the document is malformed, and reflow
// would silently corrupt it (a later opening fence gets consumed as the
// close of an earlier block, so every code block after it is reflowed as
// prose). Counting fence LINES catches this even when the fenced-content
// comparison would be vacuously equal under the same wrong pairing.
const fenceLineCount = (s) => s.split("\n").filter((l) => isFence(l)).length;

export function verify(before, after) {
  const problems = [];

  const tb = tokens(before);
  const ta = tokens(after);
  if (tb.length !== ta.length) {
    let n = 0;
    while (n < tb.length && n < ta.length && tb[n] === ta[n]) n++;
    problems.push(
      `token count ${tb.length} → ${ta.length}; first divergence at ${n}: ` +
        `expected ${JSON.stringify(tb.slice(n, n + 6).join(" "))} ` +
        `got ${JSON.stringify(ta.slice(n, n + 6).join(" "))}`
    );
  } else {
    for (let n = 0; n < tb.length; n++) {
      if (tb[n] !== ta[n]) {
        problems.push(`token ${n} changed: ${JSON.stringify(tb[n])} → ${JSON.stringify(ta[n])}`);
        break;
      }
    }
  }

  for (const [name, pred] of [
    ["headings", isHeading],
    ["table rows", isTableRow],
    ["html/comment lines", isHtml],
    ["quote paragraph breaks", isQuoteBreak],
    ["list markers", (l) => !!listMarker(l)],
  ]) {
    const b = countOf(before, pred);
    const a = countOf(after, pred);
    if (b !== a) problems.push(`${name}: ${b} → ${a}`);
  }

  // Checked first: everything below assumes fences pair correctly.
  const fbCount = fenceLineCount(before);
  if (fbCount % 2 !== 0) {
    problems.push(
      `unbalanced code fences: ${fbCount} fence lines (odd). One fence is missing its pair, ` +
        `so reflow would treat later code blocks as prose and collapse them. Fix the document first.`
    );
    return problems; // fence-dependent checks below would be meaningless
  }

  const fb = fences(before);
  const fa = fences(after);
  if (fb.length !== fa.length) {
    problems.push(`fenced blocks: ${fb.length} → ${fa.length}`);
  } else {
    for (let n = 0; n < fb.length; n++) {
      if (fb[n] !== fa[n]) {
        problems.push(`fenced block ${n} content changed`);
        break;
      }
    }
  }

  return problems;
}

/* ──────────────────────────────────  CLI  ───────────────────────────────── */

function main() {
  const [, , inputPath, outputPath] = process.argv;
  if (!inputPath || !outputPath) {
    process.stderr.write("Usage: node reflow-prose.mjs <input-file>|- <output-file>|-\n");
    process.exit(2);
  }

  let input;
  try {
    input = inputPath === "-" ? fs.readFileSync(0, "utf8") : fs.readFileSync(inputPath, "utf8");
  } catch (err) {
    process.stderr.write(`Could not read ${inputPath === "-" ? "stdin" : inputPath}: ${err.message}\n`);
    process.exit(1);
  }

  const output = reflow(input);
  const problems = verify(input, output);
  if (problems.length) {
    process.stderr.write("Reflow verification failed -- nothing written:\n");
    for (const p of problems) process.stderr.write(`  ${p}\n`);
    process.exit(1);
  }

  const inputLines = input.split("\n").length;
  const outputLines = output.split("\n").length;
  const changed = input === output ? "0" : "1";

  if (outputPath === "-") {
    // Payload on stdout, nothing else -- so `dior reflow - | pbcopy` (or any
    // other pipe) gets exactly the reflowed text, byte for byte. The summary
    // goes to stderr instead of interleaving with it.
    process.stdout.write(output);
    process.stderr.write(`${inputLines} ${outputLines} ${changed}\n`);
    return;
  }

  fs.writeFileSync(outputPath, output, "utf8");
  // Machine-readable summary line, parsed by dior's _dior_reflow -- keep this
  // format stable (space-separated: inputLines outputLines changed).
  process.stdout.write(`${inputLines} ${outputLines} ${changed}\n`);
}

main();

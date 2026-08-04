#!/usr/bin/env node
"use strict";

// Core join logic is a 1:1 port of the MarkEdit extension at
// ~/Library/Containers/app.cyan.markedit/Data/Documents/scripts/markedit-dior-unwrap.js
// (added there 2026-08-03 21:19 EDT). Two copies because they run in two different runtimes
// (MarkEdit's embedded JS engine vs. plain Node) with no shared module system between them --
// if the join rules ever change, change BOTH files and note it in each one's header comment.
//
// Usage: node unwrap-hard-breaks.js <input-file> <output-file>

function hasHardBreakMarker(rawLine) {
  if (/ {2,}$/.test(rawLine)) return true;
  const trimmed = rawLine.replace(/[ \t]+$/, "");
  if (trimmed.endsWith("\\")) {
    const run = trimmed.match(/\\+$/)[0];
    return run.length % 2 === 1;
  }
  return false;
}

function isFenceLine(line) {
  return line.match(/^\s*(```+|~~~+)/);
}

function isHeading(line) {
  return /^\s{0,3}#{1,6}(\s|$)/.test(line);
}

function isHR(line) {
  return /^\s{0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$/.test(line);
}

function isTableRow(line) {
  return /^\s*\|.*\|\s*$/.test(line) || /^\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)+$/.test(line);
}

function isHtmlLine(line) {
  return /^\s*</.test(line);
}

function listMarkerMatch(line) {
  return line.match(/^(\s*)([-*+]|\d{1,9}[.)])(\s+)/);
}

function unwrapHardBreaks(text) {
  const lines = text.split("\n");
  const out = [];
  let i = 0;
  let inFence = false;
  let fenceChar = "";
  let inFrontMatter = lines[0] !== undefined && lines[0].trim() === "---";

  let paraBuf = [];
  function flushPara() {
    if (paraBuf.length) {
      out.push(paraBuf.join(" "));
      paraBuf = [];
    }
  }

  let quoteBuf = [];
  function flushQuote() {
    if (quoteBuf.length) {
      out.push("> " + quoteBuf.join(" "));
      quoteBuf = [];
    }
  }

  let listItem = null;
  function flushListItem() {
    if (listItem) {
      out.push(listItem.prefix + listItem.textParts.join(" "));
      listItem = null;
    }
  }

  function flushAll() {
    flushPara();
    flushQuote();
    flushListItem();
  }

  while (i < lines.length) {
    const rawLine = lines[i];

    if (inFrontMatter) {
      out.push(rawLine);
      if (i > 0 && rawLine.trim() === "---") inFrontMatter = false;
      i++;
      continue;
    }

    if (inFence) {
      out.push(rawLine);
      if (rawLine.trim().startsWith(fenceChar.repeat(3))) inFence = false;
      i++;
      continue;
    }

    const fenceMatch = isFenceLine(rawLine);
    if (fenceMatch) {
      flushAll();
      out.push(rawLine);
      inFence = true;
      fenceChar = fenceMatch[1][0];
      i++;
      continue;
    }

    if (rawLine.trim() === "") {
      flushAll();
      out.push(rawLine);
      i++;
      continue;
    }

    if (isHeading(rawLine) || isHR(rawLine) || isTableRow(rawLine) || isHtmlLine(rawLine)) {
      flushAll();
      out.push(rawLine);
      i++;
      continue;
    }

    const leadingWs = rawLine.match(/^[ \t]*/)[0].length;
    if (!listItem && leadingWs >= 4) {
      flushAll();
      out.push(rawLine);
      i++;
      continue;
    }

    const bqMatch = rawLine.match(/^(\s*>)[ \t]?(.*)$/);
    if (bqMatch) {
      flushPara();
      flushListItem();
      quoteBuf.push(bqMatch[2].trim());
      if (hasHardBreakMarker(rawLine)) flushQuote();
      i++;
      continue;
    } else if (quoteBuf.length) {
      flushQuote();
    }

    const marker = listMarkerMatch(rawLine);
    if (marker) {
      flushPara();
      flushQuote();
      flushListItem();
      const afterMarker = marker[1].length + marker[2].length + marker[3].length;
      const prefix = rawLine.slice(0, afterMarker);
      const content = rawLine.slice(afterMarker);
      listItem = { prefix, textParts: [content.trim()] };
      if (hasHardBreakMarker(rawLine)) flushListItem();
      i++;
      continue;
    }

    if (listItem) {
      if (leadingWs >= 2) {
        listItem.textParts.push(rawLine.trim());
        if (hasHardBreakMarker(rawLine)) flushListItem();
        i++;
        continue;
      }
      flushListItem();
    }

    paraBuf.push(rawLine.trim());
    if (hasHardBreakMarker(rawLine)) flushPara();
    i++;
  }

  flushAll();
  return out.join("\n");
}

function main() {
  const [, , inputPath, outputPath] = process.argv;
  if (!inputPath || !outputPath) {
    process.stderr.write("Usage: node unwrap-hard-breaks.js <input-file> <output-file>\n");
    process.exit(2);
  }

  const fs = require("fs");
  let input;
  try {
    input = fs.readFileSync(inputPath, "utf8");
  } catch (err) {
    process.stderr.write(`Could not read ${inputPath}: ${err.message}\n`);
    process.exit(1);
  }

  const output = unwrapHardBreaks(input);
  fs.writeFileSync(outputPath, output, "utf8");

  const inputLines = input.split("\n").length;
  const outputLines = output.split("\n").length;
  // Machine-readable summary line, parsed by _dior_text_unwrap for its own printed message --
  // keep this format stable (space-separated: inputLines outputLines changed) if it ever changes.
  process.stdout.write(`${inputLines} ${outputLines} ${input === output ? "0" : "1"}\n`);
}

main();

#!/usr/bin/env bun
// Usage: merge-jsonc.js <base.jsonc> [overlay.jsonc ...] <out.json>
// Parses each JSONC file (comments and trailing commas allowed), deep-merges
// the overlays onto the base in order, and writes plain JSON.
import { readFileSync, writeFileSync } from 'fs';

function stripComments(str) {
  let inString = false;
  let inBlock = false;
  let inLine = false;
  let out = '';
  for (let i = 0; i < str.length; i++) {
    if (inBlock) {
      if (str[i] === '*' && str[i+1] === '/') { inBlock = false; i++; }
      continue;
    }
    if (inLine) {
      if (str[i] === '\n') { inLine = false; out += '\n'; }
      continue;
    }
    if (inString) {
      if (str[i] === '\\') { out += str[i] + str[i+1]; i++; continue; }
      if (str[i] === inString) inString = false;
      out += str[i];
      continue;
    }
    if (str[i] === '"' || str[i] === "'") { inString = str[i]; out += str[i]; continue; }
    if (str[i] === '/' && str[i+1] === '/') { inLine = true; i++; continue; }
    if (str[i] === '/' && str[i+1] === '*') { inBlock = true; i++; continue; }
    out += str[i];
  }
  return out;
}

// Drop commas directly followed (after whitespace) by `}` or `]`. Expects
// comment-free input.
function stripTrailingCommas(str) {
  let inString = false;
  let out = '';
  for (let i = 0; i < str.length; i++) {
    if (inString) {
      if (str[i] === '\\') { out += str[i] + str[i+1]; i++; continue; }
      if (str[i] === '"') inString = false;
      out += str[i];
      continue;
    }
    if (str[i] === '"') { inString = true; out += str[i]; continue; }
    if (str[i] === ',') {
      let j = i + 1;
      while (j < str.length && /\s/.test(str[j])) j++;
      if (str[j] === '}' || str[j] === ']') continue;
    }
    out += str[i];
  }
  return out;
}

function parseJsonc(file) {
  return JSON.parse(stripTrailingCommas(stripComments(readFileSync(file, 'utf8'))));
}

function deepMerge(a, b) {
  const result = { ...a };
  for (const [k, v] of Object.entries(b)) {
    if (Array.isArray(v) && Array.isArray(result[k])) {
      result[k] = [...result[k], ...v];
    } else if (v && typeof v === 'object' && !Array.isArray(v) && result[k] && typeof result[k] === 'object' && !Array.isArray(result[k])) {
      result[k] = deepMerge(result[k], v);
    } else {
      result[k] = v;
    }
  }
  return result;
}

const args = process.argv.slice(2);
if (args.length < 2) {
  console.error('usage: merge-jsonc.js <base.jsonc> [overlay.jsonc ...] <out.json>');
  process.exit(1);
}
const outFile = args.pop();
const merged = args.map(parseJsonc).reduce(deepMerge);
writeFileSync(outFile, JSON.stringify(merged, null, 2) + '\n');

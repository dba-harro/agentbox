#!/usr/bin/env python3
"""Blank the opencode logo inside the compiled opencode binary.

The opencode logo (TUI home screen + CLI banner) is baked into the compiled
bun binary as art strings. It appears in several representations:

  * template form:  glyph data uses "_ ^ ~ ," placeholder chars
                    (packages/tui/src/logo.ts), rendered at runtime
  * pre-rendered form: the displayed glyphs are stored directly
  * OpenCode 2 stores every string TWICE in the bun binary: once as UTF-8 JS
    source (block glyphs as \\uXXXX escapes) and once in the compiled bytecode
    string table, which is UTF-16LE. The runtime executes the UTF-16LE copy,
    so blanking only the UTF-8 source has no visible effect.

This script blanks ALL forms by replacing every logo glyph byte with spaces of
identical byte length. Byte length is preserved, so the binary is never
corrupted and unrelated UI glyphs (borders, scrollbars, spinners, the --mini
`go` logo) are left untouched.

Robustness against daily upstream updates:
  * Encoding-tolerant: raw UTF-8, \\uXXXX and \\u{XXXX} escapes, and UTF-16LE /
    UTF-16BE (bytecode string table) are all tried.
  * Anchors are the full logo rows, so there is no risk of colliding with
    unrelated UI that happens to use a short glyph run.
  * A post-check scans the whole binary and fails the build if any logo-sized
    run of mixed block glyphs remains. If a future release changes the logo to
    an unrecognized form, this fails loudly with the leftover string instead
    of silently leaving a visible logo.

Usage: python3 blank-logo.py ./opencode
"""

import re
import sys

# Template-form logo rows (glyph data with placeholder chars), copied
# verbatim from packages/tui/src/logo.ts:
#
#   left:  ["                   ", "█▀▀█ █▀▀█ █▀▀█ █▀▀▄",
#           "█__█ █__█ █^^^ █__█", "▀▀▀▀ █▀▀▀ ▀▀▀▀ ▀~~▀"]
#   right: ["             ▄     ", "█▀▀▀ █▀▀█ █▀▀█ █▀▀█",
#           "█___ █__█ █__█ █^^^", "▀▀▀▀ ▀▀▀▀ ▀▀▀▀ ▀▀▀▀"]
#
# left[0] is all spaces and already invisible, so it is not listed.
ART = [
    "             ▄     ",  # right[0]
    "█▀▀█ █▀▀█ █▀▀█ █▀▀▄",  # left[1]
    "█__█ █__█ █^^^ █__█",  # left[2]
    "▀▀▀▀ █▀▀▀ ▀▀▀▀ ▀~~▀",  # left[3]
    "█▀▀▀ █▀▀█ █▀▀█ █▀▀█",  # right[1]
    "█___ █__█ █__█ █^^^",  # right[2]
    "▀▀▀▀ ▀▀▀▀ ▀▀▀▀ ▀▀▀▀",  # right[3]
]

# Pre-rendered logo rows (the glyphs as actually displayed). Some releases
# bake these directly into the binary instead of the template form. The
# rendered logo is stable across releases (it is what appears on screen).
RENDERED = [
    "█▀▀█ █▀▀█ █▀▀█ █▀▀▄ █▀▀▀ █▀▀█ █▀▀█ █▀▀█",  # rendered row 1
    "█  █ █  █ █▀▀▀ █  █ █    █  █ █  █ █▀▀▀",  # rendered row 2
    "▀▀▀▀ █▀▀▀ ▀▀▀▀ ▀  ▀",  # rendered row 3 (truncated form seen in some releases)
]

# Glyph codepoints used by the logo.
GLYPH_CODEPOINTS = {0x2588, 0x2580, 0x2584}
# ASCII template characters the Logo component renders as blocks.
ASCII_GLYPHS = "_^~,"

# Encoding styles, in preference order. `raw` is UTF-8; the `utf16*` styles
# cover the bytecode string table in the bun-compiled v2 binary.
STYLES = ("uXXXX", "uXXXX-brace", "raw", "utf16le", "utf16be")

# Byte encoding used for each style ("ascii" for the escaped forms).
ENCODINGS = {"raw": "utf-8", "utf16le": "utf-16-le", "utf16be": "utf-16-be"}

# A leftover "logo-shaped" run: at least this many block glyphs using at least
# two distinct block glyphs. The logo rows are long and mix glyph types;
# scrollbars/progress bars are long but single-type, and the --mini `go` logo
# is short, so neither trips the check.
POSTCHECK_MIN_GLYPHS = 12


def tokens(line):
    toks = []
    for ch in line:
        cp = ord(ch)
        if cp in GLYPH_CODEPOINTS:
            toks.append(("glyph", cp))
        elif ch in ASCII_GLYPHS:
            toks.append(("ascii", ch))
        else:
            toks.append(("plain", ch))
    return toks


def encode(toks, style):
    out = []
    for kind, val in toks:
        if kind == "plain" or kind == "ascii":
            out.append(val)
        elif style in ("raw", "utf16le", "utf16be"):
            out.append(chr(val))
        elif style == "uXXXX":
            out.append("\\u%04x" % val)
        else:
            out.append("\\u{%x}" % val)
    return "".join(out).encode(ENCODINGS.get(style, "ascii"))


def blank(toks, style):
    out = []
    for kind, val in toks:
        if kind == "plain":
            out.append(val)
        elif kind == "ascii":
            out.append(" ")
        elif style == "raw":
            out.append(" " * len(chr(val).encode("utf-8")))
        elif style in ("utf16le", "utf16be"):
            out.append(" ")
        elif style == "uXXXX":
            out.append(" " * 6)
        else:
            out.append(" " * len("\\u{%x}" % val))
    return "".join(out).encode(ENCODINGS.get(style, "ascii"))


def blank_line(data, line):
    """Blank all occurrences of `line` in every encoding. Returns count."""
    toks = tokens(line)
    total = 0
    for style in STYLES:
        needle = encode(toks, style)
        repl = blank(toks, style)
        if len(needle) != len(repl):
            sys.exit(
                "ERROR: internal bug - blanked length differs for %r (%d != %d)"
                % (line, len(needle), len(repl))
            )
        n = data.count(needle)
        if n == 0:
            continue
        idx = 0
        while True:
            i = data.find(needle, idx)
            if i == -1:
                break
            data[i : i + len(needle)] = repl
            idx = i + len(needle)
        total += n
        print("  blanked %d %s occurrence(s) of %r" % (n, style, line))
    return total


def postcheck(data):
    """Fail if any logo-sized run of mixed block glyphs remains."""
    # Escaped (UTF-8 source) form: \u2588 \u2580 \u2584.
    pat = re.compile(rb"(?:\\u2588|\\u2580|\\u2584| )+")
    glyph_esc = (b"\\u2588", b"\\u2580", b"\\u2584")
    for m in pat.finditer(data):
        s = m.group()
        n = s.count(b"\\u2588") + s.count(b"\\u2580") + s.count(b"\\u2584")
        if n < POSTCHECK_MIN_GLYPHS:
            continue
        types = {e for e in glyph_esc if e in s}
        if len(types) < 2:
            continue
        sys.exit(
            "\n"
            "ERROR: logo glyphs are still present in the binary after blanking.\n"
            "Leftover run (%d glyphs):\n\n"
            "  %s\n\n"
            "A new opencode release probably changed the logo rendering. Add the\n"
            "exact leftover row to ART or RENDERED in %s and rebuild." % (n, s.decode("utf-8", "replace"), __file__)
        )

    # UTF-16LE bytecode string table: block glyphs are two bytes each
    # (U+2588/U+2580/U+2584 -> b"\x88\x25" / b"\x80\x25" / b"\x84\x25"),
    # spaces are b"\x20\x00". The v2 runtime executes this copy, so it must be
    # checked too.
    pat_le = re.compile(b"(?:[\x80\x84\x88]\x25|\x20\x00)+")
    glyph_le = (b"\x88\x25", b"\x80\x25", b"\x84\x25")
    for m in pat_le.finditer(data):
        s = m.group()
        n = sum(s.count(e) for e in glyph_le)
        if n < POSTCHECK_MIN_GLYPHS:
            continue
        types = {e for e in glyph_le if e in s}
        if len(types) < 2:
            continue
        sys.exit(
            "\n"
            "ERROR: UTF-16LE logo glyphs are still present in the binary after "
            "blanking.\nLeftover run (%d glyphs):\n\n"
            "  %s\n\n"
            "A new opencode release probably changed the logo rendering. Add the\n"
            "exact leftover row to ART or RENDERED in %s and rebuild." % (n, s, __file__)
        )


def main(path):
    data = bytearray(open(path, "rb").read())
    total = 0
    for art in ART:
        total += blank_line(data, art)
    for art in RENDERED:
        total += blank_line(data, art)
    with open(path, "wb") as fh:
        fh.write(bytes(data))
    postcheck(data)
    print("blank-logo: done, blanked %d logo art occurrence(s)" % total)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: python3 blank-logo.py ./opencode")
    main(sys.argv[1])
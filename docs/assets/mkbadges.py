#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 h-network
"""Generate the README badges as local SVGs.

Generated locally rather than fetched from shields.io, so the README makes no
requests outside github.com. Two styles, matching shields: `for-the-badge`
(tall, uppercase, letter-spaced) and `flat-square`.

    python3 docs/assets/mkbadges.py docs/assets/badges

Widths come from an approximate Verdana advance table, not real font metrics —
close enough at these sizes, but eyeball a render after changing any text.
"""
import sys

NARROW = "ijl.,:;|!'"
THIN = "ft()[]{}/\\-"
WIDE = "mwMW@"
UPPER = "ABCDEFGHIJKLNOPQRSTUVXYZ"

STYLES = {
    # height, font-size, letter-spacing, side padding, uppercase
    "for-the-badge": (28, 10, 1.5, 18, True),
    "flat-square": (20, 11, 0.0, 10, False),
}


def char_width(c, size):
    if c in NARROW:
        w = 3.6
    elif c in THIN:
        w = 4.6
    elif c == "r":
        w = 5.0
    elif c == " ":
        w = 4.0
    elif c == "·":
        w = 5.2
    elif c in WIDE:
        w = 10.6
    elif c in UPPER:
        w = 8.0
    else:
        w = 7.0
    return w * size / 11.0


def text_width(s, size, spacing):
    return sum(char_width(c, size) for c in s) + spacing * max(len(s) - 1, 0)


def badge(label, value, color, path, style="flat-square", label_color="#555"):
    h, fs, ls, pad, upper = STYLES[style]
    if upper:
        label, value = label.upper(), value.upper()
    lw = round(text_width(label, fs, ls)) + pad * 2
    vw = round(text_width(value, fs, ls)) + pad * 2
    w = lw + vw
    weight = "bold" if style == "for-the-badge" else "normal"
    baseline = h / 2 + fs / 2 - 1.5
    alt = f"{label}: {value}"
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" role="img" aria-label="{alt}">
  <title>{alt}</title>
  <rect width="{lw}" height="{h}" fill="{label_color}"/>
  <rect x="{lw}" width="{vw}" height="{h}" fill="{color}"/>
  <g fill="#fff" font-family="Verdana,DejaVu Sans,Geneva,sans-serif" font-size="{fs}" font-weight="{weight}" letter-spacing="{ls}" text-anchor="middle">
    <text x="{lw / 2 + ls / 2:.1f}" y="{baseline:.1f}">{label}</text>
    <text x="{lw + vw / 2 + ls / 2:.1f}" y="{baseline:.1f}">{value}</text>
  </g>
</svg>
"""
    with open(path, "w") as fh:
        fh.write(svg)
    print(f"{path}  {w}x{h}")


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "docs/assets/badges"
    B = "for-the-badge"
    F = "flat-square"

    badge("one image", "every machine", "#22C55E", f"{out}/one-image.svg", B)
    badge("registry", "ghcr.io", "#2496ED", f"{out}/registry.svg", B)
    badge("platforms", "amd64 + arm64", "#64748B", f"{out}/platforms.svg", B)
    badge("license", "Apache 2.0", "#D22128", f"{out}/license.svg", B)

    badge("Ubuntu", "24.04", "#E95420", f"{out}/ubuntu.svg", F)
    badge("Docker", "multi-arch", "#2496ED", f"{out}/docker.svg", F)
    badge("Agents", "claude codex agy", "#8B5CF6", f"{out}/agents.svg", F)
    badge("tmux", "configured", "#1BB91F", f"{out}/tmux.svg", F)
    badge("Image", "~450 MB", "#6366F1", f"{out}/size.svg", F)

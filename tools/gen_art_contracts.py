#!/usr/bin/env python3
"""Generates the pixel art added by Expansion 3 (trade contracts and dispatch).
Reuses the palette and drawing helpers from gen_art.py and only ever writes
NEW files, so existing artwork is untouched. The delivery lorries are the
existing lorry sprite recoloured, not a redesign.
Run:  python3 tools/gen_art_contracts.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from gen_art import *  # noqa: F401,F403,E402
from PIL import Image  # noqa: E402

NAVY = [(92, 128, 176, 255), (60, 96, 148, 255), (44, 72, 116, 255), (30, 48, 80, 255)]   # the lorry's livery colours (see gen_art_stainless.py)


# ------------------------------------------------------------- delivery lorries
def recolour_lorry(name, palette):
    """The existing lorry with its blue livery swapped for another colour."""
    src = Image.open(os.path.join(OUT_DIR, "lorry.png")).convert("RGBA")
    mapping = {NAVY[i]: palette[i] for i in range(4)}
    out = new(src.width, src.height)
    for y in range(src.height):
        for x in range(src.width):
            c = src.getpixel((x, y))
            out.putpixel((x, y), mapping.get(c, c))
    save(out, name)


def make_lorries():
    recolour_lorry("lorry_trade.png", ORANGE)        # small trade orders
    recolour_lorry("lorry_commercial.png", GREEN)    # commercial contracts
    recolour_lorry("lorry_major.png", RED)           # major supply agreements


# ----------------------------------------------------------------------- pallet
PALLET_W, PALLET_H, PALLET_FRAMES = 24, 22, 7        # frame k = a pallet holding k boxed cylinders (0..6)


def carton(img, x, y):
    box(img, x, y, 7, 8, CARD[1])
    rect(img, x + 1, y + 1, 5, 1, CARD[0])
    rect(img, x + 3, y + 1, 1, 6, CREAM[0])           # packing tape
    rect(img, x + 1, y + 5, 2, 2, WHITE)              # label


def make_pallet():
    sheet = new(PALLET_W * PALLET_FRAMES, PALLET_H)
    for k in range(PALLET_FRAMES):
        f = new(PALLET_W, PALLET_H)
        # wooden pallet
        rect(f, 1, 18, 22, 2, TIMBER[1])
        rect(f, 1, 18, 22, 1, TIMBER[0])
        for fx in (2, 10, 19):
            rect(f, fx, 20, 3, 2, TIMBER[2])
        frame(f, 1, 18, 22, 4, OUT)
        # boxed cylinders: bottom row left to right, then the top row
        spots = [(2, 10), (9, 10), (16, 10), (2, 2), (9, 2), (16, 2)]
        for i in range(k):
            carton(f, *spots[i])
        sheet.paste(f, (k * PALLET_W, 0))
    save(sheet, "pallet.png")


# --------------------------------------------------------------------- forklift
def make_forklift():
    sheet = new(28 * 2, 20)
    for fr in range(2):
        f = new(28, 20)
        bob = 1 if fr == 1 else 0
        rect(f, 2, 17, 22, 2, SHADOW)
        # counterweight and body
        rect(f, 0, 9 + bob, 4, 7, STEEL[3])
        rect(f, 3, 9 + bob, 15, 7, YELLOW[1])
        rect(f, 3, 9 + bob, 15, 1, YELLOW[0])
        rect(f, 3, 14 + bob, 15, 2, YELLOW[2])
        frame(f, 0, 8 + bob, 18, 9, OUT)
        # operator and overhead guard
        rect(f, 8, 6 + bob, 4, 3, ORANGE[1])              # hi-vis vest
        rect(f, 9, 3 + bob, 3, 3, SKIN)
        rect(f, 8, 2 + bob, 5, 2, YELLOW[0])              # hard hat
        rect(f, 6, 3 + bob, 1, 6, STEEL[2])
        rect(f, 14, 3 + bob, 1, 6, STEEL[2])
        rect(f, 5, 2 + bob, 11, 1, STEEL[3])
        # mast, carriage and forks
        rect(f, 18, 1, 2, 17, STEEL[2])
        rect(f, 19, 1, 1, 17, STEEL[1])
        rect(f, 18, 11, 4, 3, STEEL[3])
        rect(f, 20, 15, 8, 2, STEEL[1])
        rect(f, 20, 15, 8, 1, STEEL[0])
        frame(f, 20, 14, 8, 4, OUT)
        # wheels (spokes turn between frames)
        for wx, r in ((6, 3), (19, 2)):
            disc(f, wx, 16, r, OUT)
            disc(f, wx, 16, r - 1, (70, 66, 76, 255))
            px(f, wx + (1 if fr else -1), 16, STEEL[0])
        # beacon
        px(f, 10, 1, RED[0] if fr == 0 else RED[2])
        sheet.paste(f, (fr * 28, 0))
    save(sheet, "forklift.png")


# ------------------------------------------------------------------------ icons
def star(lit):
    f = new(7, 7)
    shape = ["...#...", "...#...", "#######", ".#####.", "..###..", ".##.##.", ".#...#."]
    base = GOLD[1] if lit else (104, 80, 66, 255)
    edge = GOLD[2] if lit else (76, 56, 52, 255)
    hi = GOLD[0] if lit else (128, 100, 80, 255)
    for y, row in enumerate(shape):
        for x, ch in enumerate(row):
            if ch == "#":
                px(f, x, y, base)
    for x, y in ((3, 1), (3, 2), (2, 3)) if lit else ((3, 1),):
        px(f, x, y, hi)
    for x, y in ((0, 2), (6, 2), (1, 6), (5, 6)):
        px(f, x, y, edge)
    return f


def make_stars():
    sheet = new(14, 7)
    sheet.paste(star(True), (0, 0))
    sheet.paste(star(False), (7, 0))
    save(sheet, "stars.png")


def icon_clipboard(size):
    f = new(size, size)
    s = size
    box(f, 1, 2, s - 2, s - 3, TIMBER[1])
    rect(f, 3, 4, s - 6, s - 7, WHITE)
    for i, yy in enumerate(range(5, s - 4, 2)):
        rect(f, 4, yy, (s - 9) if i % 2 == 0 else (s - 11), 1, STEEL[2])
    rect(f, s // 2 - 2, 0, 5, 3, STEEL[1])
    frame(f, s // 2 - 2, 0, 5, 3, OUT)
    return f


def icon_lorry(size=16):
    f = new(size, size)
    box(f, 1, 4, 9, 7, WHITE)
    rect(f, 1, 8, 9, 1, BLUE[1])
    box(f, 10, 6, 5, 5, BLUE[1])
    rect(f, 12, 7, 2, 2, SKY[0])
    for wx in (4, 12):
        disc(f, wx, 12, 2, OUT)
        px(f, wx, 12, STEEL[0])
    return f


def icon_factory(size=16):
    f = new(size, size)
    box(f, 1, 7, 14, 8, RED[1])
    for x in (2, 6, 10):                                  # saw-tooth roof
        for i in range(4):
            rect(f, x + i, 6 - i, 1, 1 + i, RED[2])
    rect(f, 11, 1, 3, 6, STEEL[2])
    frame(f, 11, 1, 3, 6, OUT)
    for x in (3, 7):
        rect(f, x, 10, 2, 2, SKY[0])
    rect(f, 11, 11, 3, 4, TIMBER[2])
    return f


def icon_clock(size=16):
    f = new(size, size)
    disc(f, 8, 8, 6, OUT)
    disc(f, 8, 8, 5, WHITE)
    rect(f, 8, 4, 1, 5, OUT)
    rect(f, 8, 8, 3, 1, OUT)
    return f


def icon_pallet(size=16):
    f = new(size, size)
    box(f, 1, 12, 14, 3, TIMBER[1])
    box(f, 2, 5, 5, 7, CARD[1])
    box(f, 7, 5, 5, 7, CARD[1])
    box(f, 4, 1, 5, 5, CARD[0])
    return f


def icon_tick(size=16):
    f = new(size, size)
    disc(f, 8, 8, 6, OUT)
    disc(f, 8, 8, 5, GREEN[1])
    for x, y in ((5, 8), (6, 9), (7, 10), (8, 9), (9, 8), (10, 7), (11, 6)):
        px(f, x, y, WHITE)
        px(f, x, y - 1, WHITE)
    return f


def icon_cross(size=16):
    f = new(size, size)
    disc(f, 8, 8, 6, OUT)
    disc(f, 8, 8, 5, RED[1])
    for i in range(5):
        for dx in (0, 1):
            px(f, 5 + i + dx, 5 + i, WHITE)
            px(f, 10 - i + dx, 5 + i, WHITE)
    return f


def icon_alert(size=16):
    f = new(size, size)
    for i in range(10):
        w = 1 + i
        rect(f, 8 - w // 2, 3 + i, w, 1, YELLOW[1])
    for i in range(10):
        w = 1 + i
        px(f, 8 - w // 2, 3 + i, OUT)
        px(f, 8 - w // 2 + w - 1, 3 + i, OUT)
    rect(f, 4, 12, 9, 1, OUT)
    rect(f, 8, 7, 1, 3, OUT)
    px(f, 8, 11, OUT)
    return f


def make_icons():
    names_funcs = [
        ("clipboard", lambda: icon_clipboard(16)), ("lorry", icon_lorry), ("factory", icon_factory), ("clock", icon_clock),
        ("pallet", icon_pallet), ("tick", icon_tick), ("cross", icon_cross), ("alert", icon_alert),
    ]
    sheet = new(16 * len(names_funcs), 16)
    for i, (_, fn) in enumerate(names_funcs):
        sheet.paste(fn(), (i * 16, 0))
    save(sheet, "contract_icons.png")
    with open(os.path.join(OUT_DIR, "contract_icons.txt"), "w") as fh:
        fh.write("\n".join(n for n, _ in names_funcs) + "\n")
    save(icon_clipboard(12), "orders_icon.png")


def main():
    make_lorries()
    make_pallet()
    make_forklift()
    make_stars()
    make_icons()
    print("contract art generated in", os.path.normpath(OUT_DIR))


if __name__ == "__main__":
    main()

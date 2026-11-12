#!/usr/bin/env python3
"""Generates every original pixel-art sprite used by Cylinder Clicker.

All art is produced procedurally by this script (no third-party assets), so
it can be tweaked and regenerated at any time:  python3 tools/gen_art.py
"""
import os
import random
import sys
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from gen_font import G as FONT  # noqa: E402

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")

# ----------------------------------------------------------------- palette
T = (0, 0, 0, 0)
OUT = (43, 31, 43, 255)
WHITE = (250, 246, 232, 255)
COPPER = [(250, 188, 120, 255), (222, 128, 54, 255), (172, 86, 34, 255), (120, 56, 26, 255)]
STEEL = [(218, 226, 232, 255), (162, 174, 186, 255), (112, 124, 138, 255), (72, 82, 96, 255)]
# Cylinder insulation: classic soft light blue (base #8FC8E8).
FOAM = [(190, 226, 244, 255), (143, 200, 232, 255), (100, 160, 202, 255), (68, 118, 162, 255)]
SCREEN_GREEN = (176, 232, 160, 255)   # control cabinet display trace
CARD = [(232, 194, 136, 255), (204, 158, 100, 255), (164, 120, 70, 255), (122, 86, 50, 255)]
TIMBER = [(206, 152, 92, 255), (176, 122, 68, 255), (138, 90, 48, 255), (98, 62, 34, 255)]
TEAL = [(96, 196, 184, 255), (52, 150, 144, 255), (34, 108, 110, 255), (24, 76, 84, 255)]
YELLOW = [(250, 220, 110, 255), (236, 184, 60, 255), (190, 136, 40, 255), (140, 96, 32, 255)]
RED = [(238, 122, 96, 255), (206, 76, 60, 255), (154, 50, 48, 255), (108, 34, 40, 255)]
BLUE = [(120, 168, 232, 255), (72, 118, 196, 255), (48, 82, 150, 255), (34, 56, 108, 255)]
GREEN = [(150, 206, 110, 255), (100, 162, 80, 255), (66, 120, 62, 255), (44, 84, 50, 255)]
ORANGE = [(250, 176, 96, 255), (232, 136, 58, 255), (184, 98, 40, 255), (130, 66, 32, 255)]
FLOOR = [(160, 157, 150, 255), (150, 147, 141, 255), (138, 135, 130, 255), (122, 119, 116, 255)]
CREAM = [(240, 230, 198, 255), (228, 214, 178, 255), (204, 188, 150, 255)]
DADO = [(98, 146, 112, 255), (80, 124, 96, 255), (60, 98, 78, 255)]
BELT = [(88, 88, 104, 255), (66, 66, 80, 255), (52, 52, 64, 255)]
SKIN = (240, 196, 150, 255)
SKY = [(196, 232, 244, 255), (150, 208, 236, 255)]
SHADOW = (40, 30, 44, 70)
GOLD = [(255, 236, 150, 255), (250, 200, 70, 255), (204, 142, 40, 255), (140, 90, 30, 255)]


def new(w, h, col=T):
    return Image.new("RGBA", (w, h), col)


def px(img, x, y, col):
    if 0 <= x < img.width and 0 <= y < img.height:
        if col[3] == 255 or col[3] == 0:
            img.putpixel((x, y), col)
        else:
            base = img.getpixel((x, y))
            a = col[3] / 255.0
            img.putpixel((x, y), tuple(int(base[i] * (1 - a) + col[i] * a) for i in range(3)) + (max(base[3], col[3]),))


def rect(img, x, y, w, h, col):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            px(img, xx, yy, col)


def frame(img, x, y, w, h, col):
    rect(img, x, y, w, 1, col)
    rect(img, x, y + h - 1, w, 1, col)
    rect(img, x, y, 1, h, col)
    rect(img, x + w - 1, y, 1, h, col)


def box(img, x, y, w, h, fill, line=OUT):
    rect(img, x, y, w, h, fill)
    frame(img, x, y, w, h, line)


def disc(img, cx, cy, r, col):
    for yy in range(-r, r + 1):
        for xx in range(-r, r + 1):
            if xx * xx + yy * yy <= r * r + r * 0.6:
                px(img, cx + xx, cy + yy, col)


def line(img, x0, y0, x1, y1, col):
    dx, dy = abs(x1 - x0), abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx - dy
    while True:
        px(img, x0, y0, col)
        if x0 == x1 and y0 == y1:
            break
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x0 += sx
        if e2 < dx:
            err += dx
            y0 += sy


def outline(img, col=OUT):
    """Adds a 1px outline around all opaque pixels."""
    src = img.copy()
    for y in range(img.height):
        for x in range(img.width):
            if src.getpixel((x, y))[3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < img.width and 0 <= ny < img.height and src.getpixel((nx, ny))[3] == 255:
                    img.putpixel((x, y), col)
                    break
    return img


def ascii_sprite(rows, pal, w=None, h=None, ox=0, oy=0):
    w = w or max(len(r) for r in rows)
    h = h or len(rows)
    img = new(w, h)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in pal:
                px(img, x + ox, y + oy, pal[ch])
    return img


def text(img, x, y, s, col, shadow=None):
    cx = x
    for ch in s:
        rows = FONT.get(ch, FONT[" "])
        for ry, row in enumerate(rows):
            for rx, c in enumerate(row):
                if c == "#":
                    if shadow:
                        px(img, cx + rx, y + ry + 1, shadow)
                    px(img, cx + rx, y + ry, col)
        cx += len(rows[0]) + 1
    return cx


def text_width(s):
    return sum(len(FONT.get(ch, FONT[" "])[0]) + 1 for ch in s) - 1


def strip(frames):
    w, h = frames[0].size
    img = new(w * len(frames), h)
    for i, f in enumerate(frames):
        img.paste(f, (i * w, 0))
    return img


def save(img, name):
    img.save(os.path.join(OUT_DIR, name))


def shade_col(pal, fx):
    if fx < 0.10:
        return pal[1]
    if fx < 0.34:
        return pal[0]
    if fx < 0.64:
        return pal[1]
    if fx < 0.86:
        return pal[2]
    return pal[3]


# ------------------------------------------------------------------- items
def cylinder_body(img, x, y, w, h, pal, top=(3, 1), bottom=(1,)):
    """Upright cylinder with metallic column shading. Returns nothing."""
    for yy in range(h):
        inset = 0
        if yy < len(top):
            inset = top[yy]
        elif yy >= h - len(bottom):
            inset = bottom[yy - (h - len(bottom))]
        for xx in range(inset, w - inset):
            px(img, x + xx, y + yy, shade_col(pal, xx / float(w - 1)))


ITEM_W, ITEM_H = 18, 22   # anchor: bottom-centre


def item_canvas():
    return new(ITEM_W, ITEM_H)


def item_sheet(small):
    img = item_canvas()
    rows = [
        "....1111111111",
        "...11111111112",
        "..111122222223",
        ".1222222222233",
        "22222222222333",
        "4444444444444.",
    ] if not small else [
        "...11111111",
        "..111111122",
        ".1122222223",
        "12222222233",
        "4444444444.",
    ]
    pal = {"1": COPPER[0], "2": COPPER[1], "3": COPPER[2], "4": COPPER[3]}
    spr = ascii_sprite(rows, pal)
    img.paste(spr, ((ITEM_W - spr.width) // 2, ITEM_H - spr.height - 2))
    if small:
        px(img, 6, ITEM_H - 6, WHITE)
        px(img, 7, ITEM_H - 6, WHITE)
    else:
        px(img, 6, ITEM_H - 7, WHITE)
        px(img, 7, ITEM_H - 7, WHITE)
        px(img, 8, ITEM_H - 7, WHITE)
    return outline(img)


def item_cylinder(kind):
    img = item_canvas()
    w, h = 12, 16
    x, y = (ITEM_W - w) // 2, ITEM_H - h - 2
    if kind == "rolled":
        cylinder_body(img, x, y + 1, w, h - 1, COPPER, top=(2, 0), bottom=(1,))
        # open top: dark ellipse
        rect(img, x + 2, y + 2, w - 4, 2, COPPER[3])
        rect(img, x + 3, y + 1, w - 6, 1, COPPER[2])
        rect(img, x + 4, y + 3, w - 8, 1, OUT)
        # unwelded seam
        rect(img, x + 6, y + 4, 1, h - 5, COPPER[3])
    elif kind in ("welded", "tested"):
        cylinder_body(img, x, y, w, h, COPPER)
        rect(img, x + 6, y + 3, 1, h - 4, COPPER[0])      # weld bead
        rect(img, x + 1, y + 3, w - 2, 1, COPPER[2])      # dome joint
        px(img, x + 2, y + 2, WHITE)
        px(img, x + 3, y + 1, WHITE)
        rect(img, x + 2, y + 5, 1, 4, WHITE)
        if kind == "tested":
            box(img, x + 7, y + 8, 5, 5, WHITE, (90, 80, 80, 255))
            px(img, x + 8, y + 10, GREEN[2])
            px(img, x + 9, y + 11, GREEN[2])
            px(img, x + 10, y + 9, GREEN[2])
            px(img, x + 10, y + 10, GREEN[2])
    elif kind == "insulated":
        cylinder_body(img, x, y, w, h, FOAM)
        px(img, x + 2, y + 2, WHITE)
        rect(img, x + 2, y + 5, 1, 3, FOAM[0])
        # speckled foam texture
        for sx, sy in ((5, 6), (8, 9), (4, 11), (7, 4), (9, 13), (6, 13)):
            px(img, x + sx, y + sy, FOAM[2])
        # copper connections
        rect(img, x + 5, y - 2, 2, 2, COPPER[1])
        px(img, x + 5, y - 2, COPPER[0])
        rect(img, x + 7, y + 10, 3, 3, COPPER[1])
        px(img, x + 7, y + 10, COPPER[0])
        px(img, x + 9, y + 12, COPPER[3])
    return outline(img)


def item_box():
    img = item_canvas()
    w, h = 14, 14
    x, y = (ITEM_W - w) // 2, ITEM_H - h - 2
    rect(img, x, y, w, 4, CARD[0])            # top face
    rect(img, x, y + 4, w, h - 4, CARD[1])    # front face
    rect(img, x + w - 3, y + 4, 3, h - 4, CARD[2])
    rect(img, x, y + h - 1, w, 1, CARD[3])
    rect(img, x + 6, y, 2, h, (244, 232, 190, 255))   # tape
    rect(img, x + 6, y + 4, 2, 1, CARD[2])
    box(img, x + 1, y + 7, 4, 4, WHITE, CARD[3])      # label
    px(img, x + 2, y + 8, COPPER[1])
    px(img, x + 3, y + 9, COPPER[1])
    rect(img, x, y + 4, w, 1, CARD[2])
    return outline(img)


def make_items():
    frames = [
        item_sheet(False), item_sheet(True), item_cylinder("rolled"), item_cylinder("welded"),
        item_cylinder("tested"), item_cylinder("insulated"), item_box(),
    ]
    save(strip(frames), "items.png")
    return frames


# ---------------------------------------------------------------- machines
MW, MH = 48, 64
BELT_Y = 46   # belt centre line inside a machine canvas


def machine_back(pal, plate_text=None):
    img = new(MW, MH)
    rect(img, 2, 36, 44, 4, SHADOW)
    # body: top face + front face
    rect(img, 3, 4, 42, 8, pal[0])
    rect(img, 3, 12, 42, 26, pal[1])
    rect(img, 3, 33, 42, 5, pal[2])
    rect(img, 3, 11, 42, 1, pal[2])
    frame(img, 3, 4, 42, 34, OUT)
    px(img, 3, 4, T), px(img, 44, 4, T)
    px(img, 4, 5, OUT), px(img, 43, 5, OUT)
    rect(img, 5, 5, 38, 1, WHITE[:3] + (90,))
    # rivets
    for rx in (6, 41):
        px(img, rx, 14, pal[2])
        px(img, rx, 31, pal[3])
    # vent grille
    for i in range(3):
        rect(img, 7, 18 + i * 3, 6, 1, pal[3])
        rect(img, 7, 19 + i * 3, 6, 1, pal[0])
    if plate_text:
        tw = text_width(plate_text)
        box(img, 24 - tw // 2 - 2, 26, tw + 4, 9, STEEL[0], STEEL[3])
        text(img, 24 - tw // 2, 27, plate_text, OUT)
    return img


def front_plate(img, pal):
    """Low guard plate in front of the belt - gives the station depth."""
    rect(img, 5, 57, 38, 5, STEEL[1])
    rect(img, 5, 57, 38, 1, STEEL[0])
    rect(img, 5, 61, 38, 1, STEEL[3])
    frame(img, 4, 56, 40, 7, OUT)
    rect(img, 8, 59, 32, 1, pal[1])
    for i in range(8, 40, 6):
        rect(img, i, 59, 3, 1, OUT)
    px(img, 6, 59, STEEL[3]), px(img, 41, 59, STEEL[3])


def m_cut():
    back = machine_back(TEAL)
    # control lever + button panel on body
    box(img := back, 30, 15, 11, 9, STEEL[2], OUT)
    px(img, 32, 17, RED[0]), px(img, 32, 18, RED[1])
    px(img, 35, 17, GREEN[0]), px(img, 35, 18, GREEN[1])
    px(img, 38, 17, YELLOW[0]), px(img, 38, 18, YELLOW[1])
    rect(img, 32, 21, 7, 1, STEEL[3])
    frames = []
    for off in (0, 5, 13, 6):
        f = new(MW, MH)
        for gx in (9, 37):   # guide rods
            rect(f, gx, 12, 2, 44, STEEL[1])
            rect(f, gx, 12, 1, 44, STEEL[0])
            frame(f, gx - 1, 11, 4, 46, OUT)
        y = 16 + off
        rect(f, 8, y, 32, 5, TEAL[1])
        rect(f, 8, y, 32, 1, TEAL[0])
        frame(f, 7, y - 1, 34, 7, OUT)
        # blade (angled edge)
        for i in range(30):
            hgt = 2 + (i * 3) // 30
            rect(f, 9 + i, y + 6, 1, hgt, STEEL[1])
            px(f, 9 + i, y + 6 + hgt - 1, STEEL[0])
            px(f, 9 + i, y + 6 + hgt, OUT)
        px(f, 8, y + 6, OUT), px(f, 8, y + 7, OUT), px(f, 39, y + 6, OUT)
        rect(f, 39, y + 6, 1, 6, OUT)
        if off == 13:
            for sx, sy in ((14, 44), (33, 43), (24, 41)):
                px(f, sx, sy, WHITE)
        front_plate(f, TEAL)
        frames.append(f)
    return back, frames


def roller(f, x, y, h, phase):
    rect(f, x, y, 7, h, STEEL[1])
    rect(f, x, y, 2, h, STEEL[0])
    rect(f, x + 5, y, 2, h, STEEL[2])
    for yy in range(y + 1, y + h - 1):
        if (yy + phase) % 4 == 0:
            rect(f, x + 1, yy, 5, 1, STEEL[3])
    frame(f, x - 1, y - 1, 9, h + 2, OUT)
    rect(f, x, y - 3, 7, 2, YELLOW[1])
    rect(f, x, y - 3, 7, 1, YELLOW[0])
    frame(f, x - 1, y - 4, 9, 4, OUT)


def m_roll():
    back = machine_back(YELLOW)
    img = back
    # big flywheel on body
    disc(img, 34, 22, 7, OUT)
    disc(img, 34, 22, 6, STEEL[2])
    disc(img, 34, 22, 4, STEEL[1])
    disc(img, 34, 22, 1, OUT)
    frames = []
    for ph in range(4):
        f = new(MW, MH)
        # spinning spokes on the flywheel
        ang = [(0, -4), (3, -3), (4, 0), (3, 3)][ph]
        line(f, 34 - ang[0], 22 - ang[1], 34 + ang[0], 22 + ang[1], STEEL[3])
        line(f, 34 + ang[1], 22 - ang[0], 34 - ang[1], 22 + ang[0], STEEL[3])
        px(f, 34, 22, OUT)
        roller(f, 7, 30, 24, ph)
        roller(f, 34, 30, 24, -ph)
        front_plate(f, YELLOW)
        frames.append(f)
    return back, frames


def m_weld():
    back = machine_back(RED)
    img = back
    # gas bottle on the body
    rect(img, 8, 14, 5, 14, BLUE[1])
    rect(img, 8, 14, 2, 14, BLUE[0])
    frame(img, 7, 13, 7, 16, OUT)
    rect(img, 9, 11, 3, 2, STEEL[1])
    frames = []
    for ph in range(4):
        f = new(MW, MH)
        dy = (0, 1, 0, 1)[ph]
        # articulated arm
        for (x0, y0, x1, y1) in ((38, 12, 40, 24 + dy), (40, 24 + dy, 33, 30 + dy)):
            for o in (-1, 0, 1):
                line(f, x0 + o, y0, x1 + o, y1, STEEL[1])
            line(f, x0 - 2, y0, x1 - 2, y1, OUT)
            line(f, x0 + 2, y0, x1 + 2, y1, OUT)
            line(f, x0 - 1, y0, x1 - 1, y1, STEEL[0])
        disc(f, 40, 24 + dy, 2, RED[1])
        px(f, 40, 24 + dy, OUT)
        disc(f, 38, 12, 2, RED[1])
        px(f, 38, 12, OUT)
        # torch tip
        rect(f, 31, 30 + dy, 3, 3, STEEL[3])
        px(f, 30, 33 + dy, YELLOW[0])
        if ph in (1, 3):
            cx, cy = 29, 35
            core = (255, 255, 255, 255)
            glow = (150, 226, 255, 255)
            rays = ((0, -3), (0, 3), (-3, 0), (3, 0)) if ph == 1 else ((-2, -2), (2, 2), (-2, 2), (2, -2))
            for rx, ry in rays:
                line(f, cx, cy, cx + rx, cy + ry, glow)
            for rx, ry in ((0, -1), (0, 1), (-1, 0), (1, 0), (0, 0)):
                px(f, cx + rx, cy + ry, core)
            sparks = ((25, 39), (33, 38), (27, 42)) if ph == 1 else ((23, 37), (32, 41), (30, 44), (26, 33))
            for sx, sy in sparks:
                px(f, sx, sy, YELLOW[0])
                px(f, sx, sy + 1, ORANGE[1])
        elif ph == 2:
            px(f, 29, 35, YELLOW[0])
            px(f, 29, 34, ORANGE[0])
        front_plate(f, RED)
        frames.append(f)
    return back, frames


def m_test():
    back = machine_back(BLUE)
    img = back
    # water tank window
    box(img, 7, 15, 10, 12, SKY[1], OUT)
    rect(img, 8, 16, 8, 3, SKY[0])
    px(img, 9, 21, WHITE), px(img, 13, 23, WHITE)
    frames = []
    needles = ((-3, -1), (-1, -3), (2, -3), (3, -1))
    for ph in range(4):
        f = new(MW, MH)
        # gauge
        disc(f, 35, 21, 6, OUT)
        disc(f, 35, 21, 5, WHITE)
        for tx, ty in ((-4, 0), (-3, -3), (0, -4), (3, -3), (4, 0)):
            px(f, 35 + tx, 21 + ty, STEEL[3])
        px(f, 38, 18, RED[1]), px(f, 39, 20, RED[1])
        nx, ny = needles[ph]
        line(f, 35, 21, 35 + nx, 21 + ny, RED[2])
        px(f, 35, 21, OUT)
        # clamp piston
        off = (0, 3, 5, 3)[ph]
        rect(f, 23, 11, 3, 14 + off, STEEL[1])
        rect(f, 23, 11, 1, 14 + off, STEEL[0])
        frame(f, 22, 10, 5, 16 + off, OUT)
        rect(f, 15, 25 + off, 19, 3, BLUE[1])
        rect(f, 15, 25 + off, 19, 1, BLUE[0])
        frame(f, 14, 24 + off, 21, 5, OUT)
        if ph == 2:
            for sx, sy in ((14, 36), (34, 38), (16, 42)):
                px(f, sx, sy, SKY[0])
                px(f, sx, sy + 1, SKY[1])
        front_plate(f, BLUE)
        frames.append(f)
    return back, frames


def m_foam():
    back = machine_back(GREEN)
    img = back
    # foam hopper on top
    rect(img, 26, 13, 14, 10, FOAM[1])
    rect(img, 26, 13, 14, 3, FOAM[0])
    frame(img, 25, 12, 16, 12, OUT)
    rect(img, 30, 24, 6, 3, STEEL[2])
    frame(img, 29, 23, 8, 5, OUT)
    frames = []
    for ph in range(4):
        f = new(MW, MH)
        for side in (0, 1):
            nx = 7 if side == 0 else 35
            rect(f, nx + 1, 40, 3, 16, STEEL[2])
            frame(f, nx, 39, 5, 18, OUT)
            rect(f, nx - 1, 34, 7, 6, GREEN[1])
            rect(f, nx - 1, 34, 7, 1, GREEN[0])
            frame(f, nx - 2, 33, 9, 8, OUT)
            tip = nx + 7 if side == 0 else nx - 3
            rect(f, tip, 36, 2, 2, STEEL[3])
        puffs = (
            (),
            ((16, 36, 1), (31, 37, 1)),
            ((17, 35, 2), (30, 36, 2), (15, 39, 1), (33, 40, 1)),
            ((18, 33, 2), (29, 34, 2), (16, 41, 1), (32, 32, 1)),
        )[ph]
        for cx, cy, r in puffs:
            disc(f, cx, cy, r, FOAM[0])
            px(f, cx, cy, WHITE)
        front_plate(f, GREEN)
        frames.append(f)
    return back, frames


def m_pack():
    back = machine_back(ORANGE)
    img = back
    # stack of flat-packed boxes on the body
    for i in range(4):
        rect(img, 7, 24 - i * 3, 12, 2, CARD[1] if i % 2 else CARD[0])
        frame(img, 6, 23 - i * 3, 14, 4, CARD[3])
    # tape reel
    disc(img, 35, 21, 5, OUT)
    disc(img, 35, 21, 4, (244, 232, 190, 255))
    disc(img, 35, 21, 1, STEEL[3])
    frames = []
    for ph in range(4):
        f = new(MW, MH)
        off = (0, 3, 6, 3)[ph]
        rect(f, 23, 11, 3, 10 + off, STEEL[1])
        frame(f, 22, 10, 5, 12 + off, OUT)
        # folding press plate with cardboard flaps
        rect(f, 14, 21 + off, 21, 4, ORANGE[1])
        rect(f, 14, 21 + off, 21, 1, ORANGE[0])
        frame(f, 13, 20 + off, 23, 6, OUT)
        flap = 2 if ph != 2 else 0
        rect(f, 13 - flap, 26 + off, 3, 3, CARD[1])
        rect(f, 33 + flap, 26 + off, 3, 3, CARD[1])
        frame(f, 12 - flap, 25 + off, 5, 5, CARD[3])
        frame(f, 32 + flap, 25 + off, 5, 5, CARD[3])
        if ph == 2:
            line(f, 35, 21, 26, 27 + off, (244, 232, 190, 255))
        front_plate(f, ORANGE)
        frames.append(f)
    return back, frames


def make_machines():
    out = {}
    for name, fn in (("cut", m_cut), ("roll", m_roll), ("weld", m_weld), ("test", m_test), ("foam", m_foam), ("pack", m_pack)):
        back, frames = fn()
        save(back, "machine_%s_back.png" % name)
        save(strip(frames), "machine_%s_front.png" % name)
        out[name] = (back, frames)
    return out


# ------------------------------------------------------- workers and extras
def make_worker():
    pal = {
        "o": OUT, "h": YELLOW[1], "H": YELLOW[0], "s": SKIN, "e": OUT, "b": BLUE[1], "B": BLUE[2],
        "w": WHITE, "k": (70, 52, 44, 255), "t": STEEL[1], "T": STEEL[3], "n": TIMBER[2],
    }
    base = [
        "....hhhh......",
        "...hHHhhh.....",
        "..hhhhhhhh....",
        "...ssssss.....",
        "...sesses.....",
        "...ssssss.....",
        "....ssss......",
        "..bbwwwwbb....",
        ".bbbbbbbbbb...",
        ".sbbbbbbbbs...",
        ".s.bbbbbb.s...",
        "...bbbbbb.....",
        "...BBBBBB.....",
        "...BB..BB.....",
        "...BB..BB.....",
        "...kk..kk.....",
    ]
    up = [
        "....hhhh..tt..",
        "...hHHhhh.tT..",
        "..hhhhhhhh.n..",
        "...ssssss..n..",
        "...sesses.sn..",
        "...ssssss.s...",
        "....ssss.bb...",
        "..bbwwwwbb....",
        ".bbbbbbbbb....",
        ".sbbbbbbb.....",
        ".s.bbbbbb.....",
        "...bbbbbb.....",
        "...BBBBBB.....",
        "...BB..BB.....",
        "...BB..BB.....",
        "...kk..kk.....",
    ]
    down = [
        "..............",
        "....hhhh......",
        "...hHHhhh.....",
        "..hhhhhhhh....",
        "...ssssss.....",
        "...sesses.....",
        "...ssssss.....",
        "..bbwwwwbb....",
        ".bbbbbbbbbbb..",
        ".sbbbbbbb.bstt",
        ".s.bbbbbb.nnTt",
        "...bbbbbb.....",
        "...BBBBBB.....",
        "...BB..BB.....",
        "...BB..BB.....",
        "...kk..kk.....",
    ]
    frames = []
    for rows in (base, up, down):
        img = new(16, 20)
        img.paste(ascii_sprite(rows, pal), (1, 2))
        outline(img)
        rect(img, 3, 19, 9, 1, SHADOW)
        frames.append(img)
    save(strip(frames), "worker.png")
    return frames


def make_cabinet():
    frames = []
    for ph in range(2):
        img = new(16, 20)
        rect(img, 2, 3, 11, 15, STEEL[1])
        rect(img, 2, 3, 11, 2, STEEL[0])
        rect(img, 10, 5, 3, 13, STEEL[2])
        box(img, 4, 6, 6, 5, (40, 60, 56, 255), OUT)
        line(img, 5, 9, 6, 8, SCREEN_GREEN)
        line(img, 6, 8, 7, 9, SCREEN_GREEN)
        px(img, 8, 7 + ph, SCREEN_GREEN)
        px(img, 4, 13, GREEN[0] if ph == 0 else GREEN[2])
        px(img, 6, 13, YELLOW[0] if ph == 1 else YELLOW[2])
        px(img, 8, 13, RED[1])
        rect(img, 4, 15, 5, 1, STEEL[3])
        outline(img)
        rect(img, 2, 19, 12, 1, SHADOW)
        frames.append(img)
    save(strip(frames), "cabinet.png")
    return frames


def make_beacon():
    frames = []
    for ph in range(2):
        img = new(12, 12)
        rect(img, 3, 8, 6, 2, STEEL[3])
        col = ORANGE if ph == 0 else YELLOW
        rect(img, 4, 4, 4, 4, col[1])
        rect(img, 4, 4, 2, 2, col[0])
        px(img, 4, 4, WHITE if ph == 1 else col[0])
        outline(img)
        if ph == 1:
            for gx, gy in ((1, 5), (10, 5), (2, 2), (9, 2), (5, 0), (6, 0)):
                px(img, gx, gy, YELLOW[0])
        frames.append(img)
    save(strip(frames), "beacon.png")
    return frames


# ------------------------------------------------------------------- belts
def make_belts():
    # horizontal belt: 16 wide tile, 22 tall (rails + legs shadow); 4 frames moving right
    frames = []
    for ph in range(4):
        img = new(16, 22)
        rect(img, 0, 2, 16, 16, BELT[1])
        for x in range(16):
            if (x - ph * 2) % 8 == 0:
                rect(img, x, 3, 1, 14, BELT[0])
            if (x - ph * 2) % 8 == 1:
                rect(img, x, 3, 1, 14, BELT[2])
        rect(img, 0, 0, 16, 1, OUT)
        rect(img, 0, 1, 16, 1, STEEL[0])
        rect(img, 0, 2, 16, 1, STEEL[2])
        rect(img, 0, 3, 16, 1, OUT)
        rect(img, 0, 16, 16, 1, OUT)
        rect(img, 0, 17, 16, 1, STEEL[1])
        rect(img, 0, 18, 16, 1, STEEL[3])
        rect(img, 0, 19, 16, 1, OUT)
        rect(img, 0, 20, 16, 2, SHADOW)
        frames.append(img)
    save(strip(frames), "belt_h.png")
    # vertical belt: 22 wide, 16 tall tile; 4 frames moving down
    vframes = []
    for ph in range(4):
        img = new(22, 16)
        rect(img, 3, 0, 16, 16, BELT[1])
        for y in range(16):
            if (y - ph * 2) % 8 == 0:
                rect(img, 4, y, 14, 1, BELT[0])
            if (y - ph * 2) % 8 == 1:
                rect(img, 4, y, 14, 1, BELT[2])
        for x0, cols in ((0, (OUT, STEEL[0], STEEL[2], OUT)), (18, (OUT, STEEL[1], STEEL[3], OUT))):
            for i, c in enumerate(cols):
                rect(img, x0 + i, 0, 1, 16, c)
        vframes.append(img)
    save(strip(vframes), "belt_v.png")
    # corner turntable plate
    c = new(22, 22)
    rect(c, 0, 0, 22, 20, STEEL[2])
    rect(c, 1, 1, 20, 18, STEEL[1])
    rect(c, 1, 1, 20, 1, STEEL[0])
    frame(c, 0, 0, 22, 20, OUT)
    for i in range(4, 18, 4):
        rect(c, i, 4, 2, 12, STEEL[3])
        rect(c, i, 4, 1, 12, STEEL[0])
    for rx, ry in ((2, 2), (19, 2), (2, 17), (19, 17)):
        px(c, rx, ry, STEEL[3])
    rect(c, 0, 20, 22, 2, SHADOW)
    save(c, "belt_corner.png")
    return frames, vframes, c


# --------------------------------------------------------------------- van
def make_van():
    img = new(72, 44)
    W = (244, 240, 228, 255)
    W2 = (214, 208, 196, 255)
    rect(img, 4, 38, 64, 4, SHADOW)
    # cargo body
    rect(img, 22, 6, 46, 28, W)
    rect(img, 22, 6, 46, 3, WHITE)
    rect(img, 22, 30, 46, 4, W2)
    # open rear: dark interior
    rect(img, 60, 9, 8, 24, (58, 46, 56, 255))
    rect(img, 61, 22, 6, 11, CARD[2])
    rect(img, 61, 22, 6, 2, CARD[0])
    rect(img, 63, 22, 1, 11, (244, 232, 190, 255))
    # copper livery stripe + logo cylinder
    rect(img, 22, 24, 38, 3, COPPER[1])
    rect(img, 22, 24, 38, 1, COPPER[0])
    cylinder_body(img, 37, 10, 8, 11, COPPER, top=(2, 1), bottom=(1,))
    frame(img, 21, 5, 48, 30, OUT)
    # cab
    rect(img, 6, 14, 16, 20, W)
    rect(img, 6, 30, 16, 4, W2)
    rect(img, 9, 12, 13, 2, W)
    rect(img, 9, 15, 10, 8, SKY[1])
    rect(img, 9, 15, 10, 2, SKY[0])
    line(img, 11, 21, 15, 16, WHITE)
    frame(img, 8, 14, 12, 10, OUT)
    line(img, 5, 18, 8, 12, OUT)
    rect(img, 8, 11, 14, 1, OUT)
    rect(img, 5, 18, 1, 17, OUT)
    rect(img, 5, 34, 17, 1, OUT)
    rect(img, 6, 15, 2, 3, T), px(img, 6, 14, T), px(img, 7, 14, T)
    rect(img, 6, 17, 1, 1, W), rect(img, 7, 15, 1, 3, W)
    rect(img, 4, 28, 2, 3, YELLOW[0])      # headlight
    rect(img, 3, 32, 4, 2, STEEL[3])       # bumper
    rect(img, 16, 25, 3, 1, STEEL[3])      # door handle
    # wheels
    for wx in (14, 52):
        disc(img, wx, 35, 5, OUT)
        disc(img, wx, 35, 3, (70, 66, 76, 255))
        disc(img, wx, 35, 1, STEEL[0])
    save(img, "van.png")
    return img


# ------------------------------------------------------------- background
BG_W, BG_H = 444, 330
WALL_H = 58


def make_background():
    rnd = random.Random(7)
    img = new(BG_W, BG_H, FLOOR[1])
    # concrete slabs
    for y in range(WALL_H, BG_H):
        for x in range(BG_W):
            sx, sy = x // 37, (y - WALL_H) // 34
            v = (sx * 7 + sy * 13) % 3
            col = (FLOOR[0], FLOOR[1], FLOOR[1])[v]
            if x % 37 == 0 or (y - WALL_H) % 34 == 0:
                col = FLOOR[2]
            img.putpixel((x, y), col)
    for _ in range(900):
        x, y = rnd.randrange(BG_W), rnd.randrange(WALL_H, BG_H)
        img.putpixel((x, y), rnd.choice((FLOOR[0], FLOOR[2], FLOOR[2])))
    for _ in range(14):   # hairline cracks / scuffs
        x, y = rnd.randrange(20, BG_W - 20), rnd.randrange(WALL_H + 20, BG_H - 10)
        for i in range(rnd.randrange(3, 9)):
            px(img, x + i, y + (i // 3) * rnd.choice((0, 1)), FLOOR[3])

    # walkway between the two production rows
    wy0, wy1 = 168, 212
    rect(img, 8, wy0, BG_W - 60, wy1 - wy0, (0, 0, 0, 14))
    for x in range(10, BG_W - 56):
        if (x // 8) % 2 == 0:
            px(img, x, wy0, YELLOW[1]), px(img, x, wy0 + 1, YELLOW[2])
            px(img, x, wy1, YELLOW[1]), px(img, x, wy1 + 1, YELLOW[2])

    # dispatch bay hazard hatching (bottom-left)
    for y in range(218, 286):
        for x in range(6, 86):
            edge = x < 9 or x > 82 or y < 221 or y > 282
            if edge:
                img.putpixel((x, y), YELLOW[1] if ((x + y) // 4) % 2 == 0 else OUT)
    # raw material bay marking (top-left)
    frame(img, 18, 100, 50, 48, YELLOW[1])
    frame(img, 19, 101, 48, 46, YELLOW[2])

    # ---- back wall
    rect(img, 0, 0, BG_W, 38, CREAM[1])
    rect(img, 0, 0, BG_W, 3, CREAM[2])
    for x in range(0, BG_W, 3):     # subtle plaster texture
        if rnd.random() < 0.3:
            px(img, x + rnd.randrange(3), rnd.randrange(4, 36), CREAM[0])
    rect(img, 0, 38, BG_W, 2, (58, 44, 40, 255))
    rect(img, 0, 40, BG_W, 14, DADO[1])
    rect(img, 0, 40, BG_W, 1, DADO[0])
    for x in range(0, BG_W, 24):
        rect(img, x, 41, 1, 13, DADO[2])
    rect(img, 0, 54, BG_W, 4, (58, 44, 40, 255))
    rect(img, 0, 54, BG_W, 1, (92, 70, 60, 255))
    rect(img, 0, WALL_H, BG_W, 5, (0, 0, 0, 40))
    rect(img, 0, WALL_H + 5, BG_W, 3, (0, 0, 0, 16))

    # windows
    for wx in (14, 98, 308, 390):
        box(img, wx, 6, 38, 28, TIMBER[2], OUT)
        rect(img, wx + 2, 8, 34, 24, SKY[1])
        rect(img, wx + 2, 8, 34, 9, SKY[0])
        # clouds
        rect(img, wx + 6, 12, 9, 2, WHITE), rect(img, wx + 8, 11, 5, 1, WHITE)
        rect(img, wx + 22, 20, 8, 2, WHITE), rect(img, wx + 24, 19, 4, 1, WHITE)
        rect(img, wx + 18, 8, 2, 24, TIMBER[2])
        rect(img, wx + 2, 19, 34, 2, TIMBER[2])
        rect(img, wx + 2, 8, 34, 1, (120, 170, 200, 255))
        rect(img, wx - 2, 34, 42, 2, TIMBER[1])
        frame(img, wx - 3, 33, 44, 4, OUT)

    # company sign
    label = "COPPERTOP CYLINDER WORKS"
    tw = text_width(label)
    sx = (BG_W - tw) // 2 - 6
    box(img, sx, 5, tw + 12, 17, TIMBER[2], OUT)
    rect(img, sx + 1, 6, tw + 10, 1, TIMBER[0])
    frame(img, sx + 2, 7, tw + 8, 13, TIMBER[3])
    text(img, sx + 6, 10, label, COPPER[0], shadow=TIMBER[3])
    sub = "EST. 1952"
    tw2 = text_width(sub)
    text(img, (BG_W - tw2) // 2, 25, sub, (150, 132, 100, 255))
    for bx in (sx + 3, sx + tw + 8):
        px(img, bx, 8, STEEL[0])
        px(img, bx, 18, STEEL[0])

    # wall clock
    disc(img, 76, 20, 8, OUT)
    disc(img, 76, 20, 7, WHITE)
    for tx, ty in ((0, -6), (6, 0), (0, 6), (-6, 0)):
        px(img, 76 + tx, 20 + ty, OUT)
    line(img, 76, 20, 76, 15, OUT)
    line(img, 76, 20, 80, 22, RED[1])

    # copper pipe run along the dado with brackets + valve
    rect(img, 0, 45, BG_W, 3, COPPER[1])
    rect(img, 0, 45, BG_W, 1, COPPER[0])
    rect(img, 0, 48, BG_W, 1, DADO[2])
    for x in range(14, BG_W, 46):
        rect(img, x, 44, 2, 5, STEEL[3])
    for vx in (206, 352):
        box(img, vx, 42, 7, 8, RED[1], OUT)
        rect(img, vx + 1, 43, 5, 1, RED[0])
        rect(img, vx + 2, 39, 3, 3, STEEL[2])
        frame(img, vx, 38, 7, 3, OUT)
        rect(img, vx + 1, 39, 5, 1, RED[0])

    # noticeboard
    box(img, 352, 8, 32, 22, (170, 130, 86, 255), TIMBER[3])
    box(img, 355, 11, 9, 11, WHITE, (150, 140, 130, 255))
    box(img, 367, 13, 12, 8, (250, 232, 150, 255), (190, 160, 90, 255))
    box(img, 358, 22, 8, 6, (190, 220, 240, 255), (120, 150, 180, 255))
    for nx, ny in ((359, 12), (372, 14), (361, 23)):
        px(img, nx, ny, RED[1])
    for ly in (15, 17, 19):
        rect(img, 357, ly, 5, 1, STEEL[2])

    # fire extinguisher
    rect(img, 433, 34, 6, 16, RED[1])
    rect(img, 433, 34, 2, 16, RED[0])
    frame(img, 432, 33, 8, 18, OUT)
    rect(img, 434, 30, 4, 3, STEEL[3])
    rect(img, 434, 40, 4, 3, WHITE)

    # ---- floor props
    # raw copper sheet pallet (top-left bay)
    def pallet(x, y, w=34, h=8):
        rect(img, x, y, w, h, TIMBER[1])
        rect(img, x, y, w, 2, TIMBER[0])
        for i in range(x + 3, x + w - 2, 8):
            rect(img, i, y + 4, 4, h - 4, TIMBER[3])
        frame(img, x - 1, y - 1, w + 2, h + 2, OUT)
        rect(img, x - 1, y + h + 1, w + 2, 2, (0, 0, 0, 50))

    pallet(26, 134)
    for i in range(6):   # stacked sheets
        yy = 130 - i * 3
        rect(img, 27, yy, 32, 3, COPPER[1] if i % 2 else COPPER[2])
        rect(img, 27, yy, 32, 1, COPPER[0])
    rect(img, 27, 109, 32, 6, COPPER[0])
    rect(img, 27, 113, 32, 2, COPPER[1])
    line(img, 33, 113, 39, 110, WHITE)
    line(img, 45, 113, 49, 111, WHITE)
    frame(img, 26, 108, 34, 26, OUT)

    # crates + plant + tea table in the middle aisle (right side)
    def crate(x, y, s=14):
        box(img, x, y, s, s, TIMBER[1], OUT)
        rect(img, x + 1, y + 1, s - 2, 3, TIMBER[0])
        frame(img, x + 2, y + 5, s - 4, s - 7, TIMBER[3])
        line(img, x + 3, y + 6, x + s - 4, y + s - 4, TIMBER[3])
        rect(img, x, y + s, s, 2, (0, 0, 0, 50))

    crate(424, 262)
    crate(424, 278, 16)
    crate(232, 296)
    crate(247, 300, 12)

    # finished-goods rack against the bottom edge
    for i in range(3):
        bx = 300 + i * 17
        box(img, bx, 298, 15, 14, CARD[1], OUT)
        rect(img, bx + 1, 299, 13, 3, CARD[0])
        rect(img, bx + 6, 299, 2, 12, (244, 232, 190, 255))
        rect(img, bx, 312, 15, 2, (0, 0, 0, 50))

    # potted plant
    def plant(x, y):
        rect(img, x + 2, y + 10, 8, 7, ORANGE[2])
        rect(img, x + 1, y + 9, 10, 2, ORANGE[1])
        frame(img, x, y + 8, 12, 10, OUT)
        px(img, x, y + 17, T if False else FLOOR[1]), px(img, x + 11, y + 17, FLOOR[1])
        for lx, ly, c in ((5, 0, GREEN[0]), (3, 2, GREEN[1]), (7, 2, GREEN[1]), (1, 4, GREEN[2]), (5, 3, GREEN[0]),
                          (9, 4, GREEN[2]), (3, 5, GREEN[1]), (7, 5, GREEN[1])):
            rect(img, x + lx, y + ly, 3, 4, c)
            frame(img, x + lx - 1, y + ly - 1, 5, 6, OUT)
            rect(img, x + lx, y + ly, 3, 4, c)
        rect(img, x, y + 18, 12, 2, (0, 0, 0, 50))

    plant(8, 62)
    plant(424, 62)

    # tea table (it is a British factory, after all)
    tx, ty = 100, 180
    rect(img, tx, ty, 34, 8, TIMBER[0])
    rect(img, tx, ty + 8, 34, 4, TIMBER[2])
    frame(img, tx - 1, ty - 1, 36, 14, OUT)
    rect(img, tx + 1, ty + 13, 3, 8, TIMBER[3]), rect(img, tx + 30, ty + 13, 3, 8, TIMBER[3])
    rect(img, tx - 1, ty + 21, 36, 2, (0, 0, 0, 40))
    # kettle
    box(img, tx + 4, ty - 6, 9, 9, STEEL[1], OUT)
    rect(img, tx + 5, ty - 5, 2, 7, STEEL[0])
    rect(img, tx + 13, ty - 4, 3, 1, OUT)
    rect(img, tx + 6, ty - 8, 5, 2, OUT)
    px(img, tx + 15, ty - 9, WHITE), px(img, tx + 16, ty - 11, WHITE), px(img, tx + 15, ty - 13, WHITE)
    # mugs
    for mx, c in ((18, RED[1]), (25, BLUE[1])):
        box(img, tx + mx, ty - 2, 5, 6, c, OUT)
        px(img, tx + mx + 5, ty, OUT), px(img, tx + mx + 5, ty + 1, OUT)
        rect(img, tx + mx + 1, ty - 1, 3, 1, (120, 80, 50, 255))

    # sleeping factory cat on a crate
    crate(160, 184, 16)
    cat = [
        "..........oo..",
        ".oo......oggo.",
        "ogo.ooooogGgo.",
        "oggogggggggo..",
        ".oggggGgggo...",
        "..oooooooo....",
    ]
    cs = ascii_sprite(cat, {"o": OUT, "g": (232, 150, 70, 255), "G": (250, 196, 120, 255)})
    img.alpha_composite(cs, (161, 179))

    # tool board on the wall (right)
    box(img, 246, 40, 36, 13, (120, 96, 80, 255), OUT)
    for i, c in enumerate((STEEL[0], RED[1], STEEL[1], YELLOW[1], STEEL[0])):
        rect(img, 250 + i * 6, 43, 2, 7, c)
        px(img, 250 + i * 6, 42, STEEL[3])

    # side + bottom walls (top-down brick edging)
    for x in range(0, 5):
        for y in range(WALL_H, BG_H):
            img.putpixel((x, y), (116, 70, 60, 255) if (y // 6 + x // 3) % 2 else (134, 84, 70, 255))
            img.putpixel((BG_W - 1 - x, y), (116, 70, 60, 255) if (y // 6 + x // 3) % 2 else (134, 84, 70, 255))
    rect(img, 5, WALL_H, 1, BG_H - WALL_H, OUT)
    rect(img, BG_W - 6, WALL_H, 1, BG_H - WALL_H, OUT)
    for y in range(BG_H - 5, BG_H):
        for x in range(BG_W):
            img.putpixel((x, y), (116, 70, 60, 255) if (x // 8 + y // 3) % 2 else (134, 84, 70, 255))
    rect(img, 0, BG_H - 6, BG_W, 1, OUT)
    # roller-door opening in the left wall behind the van
    rect(img, 0, 226, 5, 52, (40, 34, 44, 255))
    rect(img, 0, 224, 6, 2, YELLOW[1]), rect(img, 0, 278, 6, 2, YELLOW[1])

    save(img, "factory_bg.png")
    return img


# ------------------------------------------------------------------- icons
def icon_tile(pal, sym_rows, sym_col=WHITE):
    img = new(16, 16)
    rect(img, 1, 1, 14, 14, pal[1])
    rect(img, 1, 1, 14, 2, pal[0])
    rect(img, 1, 13, 14, 2, pal[2])
    frame(img, 0, 0, 16, 16, OUT)
    for cx, cy in ((0, 0), (15, 0), (0, 15), (15, 15)):
        px(img, cx, cy, T)
    for cx, cy in ((1, 1), (14, 1), (1, 14), (14, 14)):
        px(img, cx, cy, OUT)
    h = len(sym_rows)
    w = max(len(r) for r in sym_rows)
    ox, oy = (16 - w) // 2, (16 - h) // 2
    for y, row in enumerate(sym_rows):
        for x, ch in enumerate(row):
            if ch == "#":
                px(img, ox + x, oy + y + 1, pal[3])
    for y, row in enumerate(sym_rows):
        for x, ch in enumerate(row):
            if ch == "#":
                px(img, ox + x, oy + y, sym_col)
            elif ch == "c":
                px(img, ox + x, oy + y, COPPER[1])
            elif ch == "y":
                px(img, ox + x, oy + y, YELLOW[0])
    return img


ICONS = {
    "hand_tools": (TIMBER, ["..####..", ".######.", ".######.", "...##...", "...##...", "...##...", "...##...", "...##..."]),
    "finish": (COPPER, ["...#....", "...#....", ".#####..", "...#..#.", "...#.###", "......#.", ".#......", "###....."]),
    "conveyor": (STEEL, ["........", ".######.", "#.#..#.#", "#......#", "#.#..#.#", ".######.", "........", "........"]),
    "whistle": (RED, ["........", "..#.....", ".###....", "########", "###..###", "###..###", ".######.", "........"]),
    "lean": (BLUE, ["..####..", "...##...", ".######.", "#..#...#", "#..#...#", "#..###.#", "#......#", ".######."]),
    "cut": (TEAL, ["#......#", "##....##", ".##..##.", "..####..", "...##...", "..#..#..", ".#.##.#.", ".##..##."]),
    "roll": (YELLOW, [".######.", "#......#", "#.####.#", "#.#..#.#", "#.#..#.#", "#.####.#", "#......#", ".######."]),
    "weld": (RED, ["...#....", "#..#..#.", ".#.#.#..", "..yyy...", "##yyy##.", "..yyy...", ".#.#.#..", "#..#..#."]),
    "test": (BLUE, [".######.", "#......#", "#....#.#", "#...#..#", "#..#...#", "#......#", "#.#..#.#", ".######."]),
    "foam": (GREEN, ["..#...#.", ".###.###", "########", "########", ".######.", "..####..", "...##...", "...##..."]),
    "pack": (ORANGE, ["########", "#..##..#", "########", "#..##..#", "#..##..#", "#..##..#", "#..##..#", "########"]),
    "lock": (STEEL, ["..####..", ".#....#.", ".#....#.", "########", "###..###", "###..###", "########", "########"]),
    "product": (TEAL, ["..cccc..", ".cccccc.", ".cccccc.", ".cccccc.", ".cccccc.", ".cccccc.", ".cccccc.", "..cccc.."]),
    # --- stainless plant
    "s_prep": (STEEL, [".######.", "#......#", "#.####.#", "#.#..#.#", "#.#.##.#", "#.#....#", "#.######", ".#......"]),
    "s_laser": (RED, ["..####..", "..####..", "...##...", "...yy...", "...yy...", "#..yy..#", ".#.yy.#.", "########"]),
    "s_form": (YELLOW, [".##..##.", "#..##..#", "#..##..#", ".##..##.", "........", "..####..", ".#....#.", "..####.."]),
    "s_tig": (BLUE, ["#......#", ".#....#.", "..#yy#..", "..yyyy..", "..yyyy..", "..#yy#..", ".#....#.", "#......#"]),
    "s_coil": (ORANGE, [".######.", "#.......", ".######.", ".......#", ".######.", "#.......", ".######.", ".......#"]),
    "s_qa": (GREEN, ["........", ".......#", "......##", "#....##.", "##..##..", ".####...", "..##....", "........"]),
    "s_case": (BLUE, ["..####..", ".######.", "########", "#.####.#", "#.####.#", "########", ".######.", "..####.."]),
    "s_ship": (TIMBER, ["...##...", ".##..##.", "#..##..#", "#.#..#.#", "#..##..#", "#...#..#", ".##.#.##", "...##..."]),
    "s_finish": (STEEL, ["...#....", "..###...", ".#####..", "..###.#.", "...#.###", "......#.", ".#......", "###....."]),
    "s_steel": (STEEL, ["........", "########", "#......#", "########", "#......#", "########", "#......#", "########"]),
    "s_energy": (GREEN, ["....##..", "...##...", "..##....", ".######.", "....##..", "...##...", "..##....", ".##....."]),
}


def make_icons():
    names = list(ICONS.keys())
    frames = [icon_tile(*ICONS[n]) for n in names]
    save(strip(frames), "icons.png")
    with open(os.path.join(OUT_DIR, "icons.txt"), "w") as f:
        f.write("\n".join(names) + "\n")
    return frames


def make_ui_bits():
    # coin (12x12)
    coin = [
        "...oooooo...",
        "..o111111o..",
        ".o11222221o.",
        "o1122112222o",
        "o1221222232o",
        "o1221222232o",
        "o1221222232o",
        "o1221222232o",
        "o1222112232o",
        ".o22222233o.",
        "..o333333o..",
        "...oooooo...",
    ]
    save(ascii_sprite(coin, {"o": GOLD[3], "1": GOLD[0], "2": GOLD[1], "3": GOLD[2]}), "coin.png")
    # gear (12x12)
    gear = [
        "....o##o....",
        ".oo.o##o.oo.",
        "o##o####o##o",
        "o##########o",
        ".o###oo###o.",
        "o###o..o###o",
        "o###o..o###o",
        ".o###oo###o.",
        "o##########o",
        "o##o####o##o",
        ".oo.o##o.oo.",
        "....o##o....",
    ]
    save(ascii_sprite(gear, {"o": OUT, "#": CREAM[0]}), "gear.png")
    # warning bubble (9x10) for blocked stations
    warn = [
        ".ooooooo.",
        "o1111111o",
        "o111o111o",
        "o111o111o",
        "o111o111o",
        "o1111111o",
        "o111o111o",
        ".ooooooo.",
        "....o....",
    ]
    save(ascii_sprite(warn, {"o": OUT, "1": YELLOW[0]}), "warn.png")
    # small cylinder icon for the HUD (10x12)
    spr = new(10, 13)
    cylinder_body(spr, 1, 1, 8, 11, COPPER, top=(2, 1), bottom=(1,))
    outline(spr)
    save(spr, "cyl_icon.png")
    # spark particle (5x5)
    sp = ["..1..", "..1..", "11111", "..1..", "..1.."]
    save(ascii_sprite(sp, {"1": (255, 244, 190, 255)}), "spark.png")


def make_app_icon(items):
    img = new(64, 64)
    rect(img, 2, 2, 60, 60, TEAL[1])
    rect(img, 2, 2, 60, 6, TEAL[0])
    rect(img, 2, 54, 60, 8, TEAL[2])
    frame(img, 0, 0, 64, 64, OUT)
    frame(img, 1, 1, 62, 62, OUT)
    spr = new(16, 20)
    cylinder_body(spr, 2, 2, 12, 16, COPPER)
    px(spr, 4, 4, WHITE), rect(spr, 4, 7, 1, 4, WHITE)
    outline(spr)
    big = spr.resize((48, 60), Image.NEAREST)
    img.alpha_composite(big, (8, 2))
    out_path = os.path.join(os.path.dirname(__file__), "..", "icon.png")
    img.resize((128, 128), Image.NEAREST).save(out_path)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    items = make_items()
    make_machines()
    make_worker()
    make_cabinet()
    make_beacon()
    make_belts()
    make_van()
    make_background()
    make_icons()
    make_ui_bits()
    make_app_icon(items)
    print("art generated in", os.path.normpath(OUT_DIR))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generates the original pixel art for the Stainless Steel Plant and the
factory overview thumbnails. Reuses the drawing helpers and palette from
gen_art.py.  Run:  python3 tools/gen_art_stainless.py
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from gen_art import *  # noqa: F401,F403,E402

WALL = [(244, 247, 250, 255), (230, 235, 240, 255), (204, 212, 222, 255)]
NAVY = [(92, 128, 176, 255), (60, 96, 148, 255), (44, 72, 116, 255), (30, 48, 80, 255)]
EPOXY = [(190, 200, 208, 255), (178, 189, 198, 255), (164, 176, 186, 255), (144, 156, 168, 255)]
PANEL = [(248, 250, 252, 255), (226, 232, 238, 255), (192, 202, 214, 255), (150, 162, 178, 255)]
PURPLE = [(190, 150, 226, 255), (146, 104, 190, 255), (104, 72, 146, 255), (72, 48, 104, 255)]
SCREEN = (34, 46, 58, 255)
LASER = (255, 80, 90, 255)
ARC = (150, 226, 255, 255)
WHITE_HOT = (255, 255, 255, 255)
DARKSTEEL = (58, 66, 80, 255)


# ------------------------------------------------------------------- items
def steel_sheet(pal, small, holes=False):
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
    spr = ascii_sprite(rows, {"1": pal[0], "2": pal[1], "3": pal[2], "4": pal[3]})
    ox, oy = (ITEM_W - spr.width) // 2, ITEM_H - spr.height - 2
    img.paste(spr, (ox, oy))
    if holes:
        px(img, ox + 4, oy + 2, pal[3]), px(img, ox + 7, oy + 1, pal[3])
    return img


def steel_cylinder(kind):
    img = item_canvas()
    w, h = 12, 18
    x, y = (ITEM_W - w) // 2, ITEM_H - h - 2
    if kind == "rolled":
        cylinder_body(img, x, y + 1, w, h - 1, STEEL, top=(2, 0), bottom=(1,))
        rect(img, x + 2, y + 2, w - 4, 2, STEEL[3])
        rect(img, x + 3, y + 1, w - 6, 1, STEEL[2])
        rect(img, x + 4, y + 3, w - 8, 1, OUT)
        rect(img, x + 6, y + 4, 1, h - 5, STEEL[3])
        rect(img, x + 2, y + 6, 1, 5, WHITE)
        return outline(img)
    if kind == "cased":
        cylinder_body(img, x, y, w, h, FOAM)
        # white outer casing rings top and bottom
        for yy in (y + 3, y + 4, y + h - 4, y + h - 3):
            for xx in range(w):
                px(img, x + xx, yy, shade_col(PANEL, xx / float(w - 1)))
        px(img, x + 2, y + 2, WHITE)
        rect(img, x + 2, y + 6, 1, 5, FOAM[0])
        for sx, sy in ((5, 8), (8, 11), (4, 12), (7, 7)):
            px(img, x + sx, y + sy, FOAM[2])
        rect(img, x + 4, y - 2, 2, 2, COPPER[1]), px(img, x + 4, y - 2, COPPER[0])
        rect(img, x + 7, y - 2, 2, 2, COPPER[1]), px(img, x + 7, y - 2, COPPER[0])
        box(img, x + 6, y + 9, 5, 4, PANEL[0], PANEL[3])     # control box
        px(img, x + 8, y + 10, RED[1])
        return outline(img)
    cylinder_body(img, x, y, w, h, STEEL)
    rect(img, x + 6, y + 3, 1, h - 4, (150, 190, 226, 255))   # TIG seam with heat tint
    rect(img, x + 1, y + 3, w - 2, 1, STEEL[2])
    rect(img, x + 1, y + h - 3, w - 2, 1, STEEL[2])
    px(img, x + 2, y + 2, WHITE), px(img, x + 3, y + 1, WHITE)
    rect(img, x + 2, y + 5, 1, 6, WHITE)
    rect(img, x + 3, y + 6, 1, 3, STEEL[0])
    if kind in ("coiled", "tested"):
        rect(img, x + 4, y - 2, 2, 2, COPPER[1]), px(img, x + 4, y - 2, COPPER[0])
        rect(img, x + 7, y - 2, 2, 2, COPPER[1]), px(img, x + 7, y - 2, COPPER[0])
        rect(img, x + 8, y + 12, 3, 3, COPPER[1]), px(img, x + 8, y + 12, COPPER[0]), px(img, x + 10, y + 14, COPPER[3])
    if kind == "tested":
        box(img, x + 7, y + 6, 5, 5, WHITE, (90, 80, 80, 255))
        px(img, x + 8, y + 8, GREEN[2]), px(img, x + 9, y + 9, GREEN[2])
        px(img, x + 10, y + 7, GREEN[2]), px(img, x + 10, y + 8, GREEN[2])
    return outline(img)


def steel_box():
    img = item_canvas()
    w, h = 14, 17
    x, y = (ITEM_W - w) // 2, ITEM_H - h - 2
    rect(img, x, y, w, 4, CARD[0])
    rect(img, x, y + 4, w, h - 4, CARD[1])
    rect(img, x + w - 3, y + 4, 3, h - 4, CARD[2])
    rect(img, x, y + h - 1, w, 1, CARD[3])
    rect(img, x, y + 4, w, 1, CARD[2])
    for sx in (3, 10):                       # steel strapping
        rect(img, x + sx, y, 1, h, NAVY[1])
    box(img, x + 5, y + 7, 5, 6, WHITE, NAVY[2])     # label
    rect(img, x + 6, y + 8, 3, 1, NAVY[1])
    px(img, x + 6, y + 10, FOAM[2]), px(img, x + 7, y + 11, FOAM[2]), px(img, x + 8, y + 10, FOAM[2])
    return outline(img)


def make_items_stainless():
    dull = [STEEL[1], STEEL[2], STEEL[3], (56, 64, 76, 255)]
    raw = outline(steel_sheet(dull, False))
    prepped = steel_sheet(STEEL, False)
    for gx in (6, 7, 8):
        px(prepped, gx, ITEM_H - 7, WHITE)
    px(prepped, 11, ITEM_H - 6, WHITE)
    outline(prepped)
    cut = steel_sheet(STEEL, True, holes=True)
    px(cut, 6, ITEM_H - 6, WHITE), px(cut, 7, ITEM_H - 6, WHITE)
    outline(cut)
    frames = [raw, prepped, cut, steel_cylinder("rolled"), steel_cylinder("welded"), steel_cylinder("coiled"),
              steel_cylinder("tested"), steel_cylinder("cased"), steel_box()]
    save(strip(frames), "items_stainless.png")


# ---------------------------------------------------------------- machines
def back2(accent, screen_rows=None):
    """A modern enclosed cell: white panels, accent band, status screen."""
    img = new(MW, MH)
    rect(img, 2, 36, 44, 4, SHADOW)
    rect(img, 3, 4, 42, 8, PANEL[0])
    rect(img, 3, 12, 42, 26, PANEL[1])
    rect(img, 3, 33, 42, 5, PANEL[2])
    rect(img, 3, 11, 42, 1, PANEL[2])
    rect(img, 3, 6, 42, 3, accent[1])
    rect(img, 3, 6, 42, 1, accent[0])
    rect(img, 3, 30, 42, 2, accent[1])
    frame(img, 3, 4, 42, 34, OUT)
    px(img, 3, 4, T), px(img, 44, 4, T)
    px(img, 4, 5, OUT), px(img, 43, 5, OUT)
    for x in (16, 30):                      # panel seams
        rect(img, x, 12, 1, 18, PANEL[2])
    for rx in (6, 41):
        px(img, rx, 14, PANEL[3]), px(img, rx, 27, PANEL[3])
    # status screen
    box(img, 31, 14, 11, 9, SCREEN, OUT)
    rows = screen_rows or ["g.g.g", ".ggg.", "g...g"]
    for ry, row in enumerate(rows):
        for rx, ch in enumerate(row):
            if ch == "g":
                px(img, 33 + rx, 16 + ry * 2, (120, 240, 150, 255))
            elif ch == "b":
                px(img, 33 + rx, 16 + ry * 2, ARC)
            elif ch == "r":
                px(img, 33 + rx, 16 + ry * 2, LASER)
    px(img, 33, 25, GREEN[0]), px(img, 36, 25, YELLOW[0]), px(img, 39, 25, RED[1])
    return img


def plate2(img, accent):
    rect(img, 5, 57, 38, 5, STEEL[1])
    rect(img, 5, 57, 38, 1, STEEL[0])
    rect(img, 5, 61, 38, 1, STEEL[3])
    frame(img, 4, 56, 40, 7, OUT)
    rect(img, 8, 59, 32, 1, accent[1])
    for i in range(8, 40, 8):
        rect(img, i, 59, 2, 1, WHITE)
    px(img, 6, 59, STEEL[3]), px(img, 41, 59, STEEL[3])


def s_prep():
    back = back2(NAVY, ["b.b.b", "bbbbb", "b.b.b"])
    # degreasing tank on the body
    box(back, 6, 14, 9, 13, SKY[1], OUT)
    rect(back, 7, 15, 7, 3, SKY[0])
    frames = []
    for ph in range(4):
        f = new(MW, MH)
        # steel coil on a spindle, rotating
        cx, cy = 13, 30
        disc(f, cx, cy, 9, OUT)
        disc(f, cx, cy, 8, STEEL[1])
        disc(f, cx, cy, 6, STEEL[2])
        disc(f, cx, cy, 4, STEEL[1])
        disc(f, cx, cy, 2, DARKSTEEL)
        for a in range(4):
            dx, dy = [(0, -7), (5, -5), (7, 0), (5, 5), (0, 7), (-5, 5), (-7, 0), (-5, -5)][(a * 2 + ph) % 8]
            px(f, cx + dx, cy + dy, WHITE)
        px(f, cx - 3, cy - 5, WHITE)
        # strip feeding down onto the belt + leveller rollers
        line(f, 20, 34, 24, 42, STEEL[0])
        line(f, 21, 34, 25, 42, STEEL[2])
        for rx in (30, 36):
            disc(f, rx, 36, 3, OUT)
            disc(f, rx, 36, 2, STEEL[1])
            px(f, rx + (ph % 2) - 1, 35 + (ph // 2), WHITE)
        rect(f, 27, 31, 13, 2, NAVY[1])
        frame(f, 26, 30, 15, 4, OUT)
        if ph % 2 == 1:
            for sx, sy in ((28, 41), (33, 43), (38, 40)):
                px(f, sx, sy, SKY[0])
        plate2(f, NAVY)
        frames.append(f)
    return back, frames


def s_laser():
    back = back2(RED, ["r...r", ".r.r.", "..r.."])
    box(back, 6, 15, 8, 6, YELLOW[1], OUT)        # laser warning label
    px(back, 9, 16, OUT), px(back, 10, 17, OUT), px(back, 9, 18, OUT), px(back, 10, 19, OUT)
    frames = []
    for ph in range(4):
        f = new(MW, MH)
        for gx in (6, 40):                         # gantry legs
            rect(f, gx, 14, 2, 42, STEEL[1])
            rect(f, gx, 14, 1, 42, STEEL[0])
            frame(f, gx - 1, 13, 4, 44, OUT)
        rect(f, 5, 15, 38, 4, STEEL[1])
        rect(f, 5, 15, 38, 1, STEEL[0])
        frame(f, 4, 14, 40, 6, OUT)
        hx = (13, 20, 27, 20)[ph]
        box(f, hx, 18, 9, 9, DARKSTEEL, OUT)
        rect(f, hx + 1, 19, 7, 2, RED[1])
        px(f, hx + 4, 24, LASER)
        rect(f, hx + 3, 27, 3, 2, STEEL[3])
        bx = hx + 4
        for yy in range(29, 44):                   # the beam
            px(f, bx, yy, LASER)
            px(f, bx - 1, yy, (255, 80, 90, 70))
            px(f, bx + 1, yy, (255, 80, 90, 70))
        for dx, dy in ((0, 0), (-1, 0), (1, 0), (0, -1)):
            px(f, bx + dx, 44 + dy, WHITE_HOT)
        sparks = (((-3, -2), (3, -3), (2, 1)), ((-2, -4), (4, -1), (-4, 0)))[ph % 2]
        for dx, dy in sparks:
            px(f, bx + dx, 44 + dy, YELLOW[0])
        plate2(f, RED)
        frames.append(f)
    return back, frames


def roller2(f, x, y, h, phase, cap):
    rect(f, x, y, 7, h, STEEL[1])
    rect(f, x, y, 2, h, STEEL[0])
    rect(f, x + 5, y, 2, h, STEEL[2])
    for yy in range(y + 1, y + h - 1):
        if (yy + phase) % 4 == 0:
            rect(f, x + 1, yy, 5, 1, STEEL[3])
    frame(f, x - 1, y - 1, 9, h + 2, OUT)
    rect(f, x, y - 3, 7, 2, cap[1])
    rect(f, x, y - 3, 7, 1, cap[0])
    frame(f, x - 1, y - 4, 9, 4, OUT)


def s_form():
    back = back2(YELLOW, ["g....", "gg...", "ggg.."])
    disc(back, 13, 21, 6, OUT)
    disc(back, 13, 21, 5, STEEL[2])
    disc(back, 13, 21, 3, STEEL[1])
    frames = []
    for ph in range(4):
        f = new(MW, MH)
        ang = [(0, -3), (2, -2), (3, 0), (2, 2)][ph]
        line(f, 13 - ang[0], 21 - ang[1], 13 + ang[0], 21 + ang[1], STEEL[3])
        line(f, 13 + ang[1], 21 - ang[0], 13 - ang[1], 21 + ang[0], STEEL[3])
        # overhead pinch roll on a yoke + two side rolls
        rect(f, 8, 24, 32, 3, YELLOW[1])
        rect(f, 8, 24, 32, 1, YELLOW[0])
        frame(f, 7, 23, 34, 5, OUT)
        roller2(f, 7, 32, 22, ph, YELLOW)
        roller2(f, 34, 32, 22, -ph, YELLOW)
        rect(f, 19, 28, 10, 3, STEEL[1])
        for xx in range(19, 29):
            if (xx + ph) % 3 == 0:
                px(f, xx, 29, STEEL[3])
        frame(f, 18, 27, 12, 5, OUT)
        plate2(f, YELLOW)
        frames.append(f)
    return back, frames


def s_tig():
    back = back2(TEAL, ["b.b.b", ".b.b.", "b.b.b"])
    for i, bx in enumerate((6, 12)):               # argon bottles
        rect(back, bx, 13, 5, 15, NAVY[1])
        rect(back, bx, 13, 2, 15, NAVY[0])
        frame(back, bx - 1, 12, 7, 17, OUT)
        rect(back, bx + 1, 10, 3, 2, STEEL[1])
    frames = []
    orbit = ((11, 40), (19, 44), (29, 44), (36, 40))
    for ph in range(4):
        f = new(MW, MH)
        for gx in (5, 41):
            rect(f, gx, 20, 2, 36, STEEL[1])
            frame(f, gx - 1, 19, 4, 38, OUT)
        # orbital ring: the half in front of the vessel
        for xx in range(-18, 19):
            yy = int(round(5 * (1 - (xx / 18.0) ** 2) ** 0.5))
            px(f, 24 + xx, 39 + yy, STEEL[1])
            px(f, 24 + xx, 40 + yy, STEEL[3])
            px(f, 24 + xx, 38 + yy, OUT)
            px(f, 24 + xx, 41 + yy, OUT)
        tx, ty = orbit[ph]
        box(f, tx - 2, ty - 3, 5, 5, TEAL[1], OUT)   # travelling torch head
        px(f, tx, ty - 2, TEAL[0])
        ax, ay = tx + (1 if tx < 24 else -1) * 3, ty - 4
        rays = ((0, -3), (0, 3), (-3, 0), (3, 0)) if ph % 2 == 0 else ((-2, -2), (2, 2), (-2, 2), (2, -2))
        for rx, ry in rays:
            line(f, ax, ay, ax + rx, ay + ry, ARC)
        for rx, ry in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            px(f, ax + rx, ay + ry, WHITE_HOT)
        px(f, ax + 2, ay + 4, (190, 240, 255, 255))
        plate2(f, TEAL)
        frames.append(f)
    return back, frames


def s_coil():
    back = back2(ORANGE, ["g.g.g", "g.g.g", "ggggg"])
    # rack of spare copper coils
    for i in range(3):
        yy = 14 + i * 5
        rect(back, 6, yy, 9, 3, COPPER[1])
        rect(back, 6, yy, 9, 1, COPPER[0])
        for xx in range(7, 15, 2):
            px(back, xx, yy + 1, COPPER[3])
        frame(back, 5, yy - 1, 11, 5, OUT)
    frames = []
    for ph in range(4):
        f = new(MW, MH)
        off = (0, 4, 8, 4)[ph]
        rect(f, 23, 11, 3, 6 + off, STEEL[1])
        rect(f, 23, 11, 1, 6 + off, STEEL[0])
        frame(f, 22, 10, 5, 8 + off, OUT)
        box(f, 19, 17 + off, 11, 4, ORANGE[1], OUT)       # gripper
        rect(f, 20, 18 + off, 9, 1, ORANGE[0])
        # the copper coil being lowered into the vessel
        cy = 21 + off
        for i in range(4):
            yy = cy + i * 2
            if yy < 31:                                    # disappears into the shell
                rect(f, 20, yy, 9, 1, COPPER[1] if i % 2 == 0 else COPPER[2])
                px(f, 20, yy, COPPER[0])
                px(f, 19 if i % 2 == 0 else 29, yy + 1, COPPER[3])
        if ph == 2:
            for sx, sy in ((16, 32), (32, 31)):
                px(f, sx, sy, YELLOW[0]), px(f, sx, sy + 1, ORANGE[1])
        plate2(f, ORANGE)
        frames.append(f)
    return back, frames


def s_qa():
    back = back2(GREEN, ["....g", "g..g.", ".gg.."])
    # big pressure gauge
    disc(back, 11, 21, 6, OUT)
    disc(back, 11, 21, 5, WHITE)
    for tx, ty in ((-4, 0), (-3, -3), (0, -4), (3, -3), (4, 0)):
        px(back, 11 + tx, 21 + ty, STEEL[3])
    px(back, 14, 18, RED[1])
    frames = []
    needles = ((-3, -1), (-1, -3), (2, -3), (3, -1))
    for ph in range(4):
        f = new(MW, MH)
        nx, ny = needles[ph]
        line(f, 11, 21, 11 + nx, 21 + ny, RED[2])
        px(f, 11, 21, OUT)
        # inspection frame with a sweeping scan line
        for gx in (8, 38):
            rect(f, gx, 26, 2, 30, STEEL[1])
            rect(f, gx, 26, 1, 30, STEEL[0])
            frame(f, gx - 1, 25, 4, 32, OUT)
            box(f, gx - 1, 27, 4, 4, DARKSTEEL, OUT)
        sy = (30, 36, 42, 36)[ph]
        rect(f, 11, sy, 26, 1, (140, 255, 160, 255))
        rect(f, 11, sy - 1, 26, 1, (140, 255, 160, 80))
        rect(f, 11, sy + 1, 26, 1, (140, 255, 160, 80))
        px(f, 11, sy, WHITE_HOT), px(f, 36, sy, WHITE_HOT)
        # hose clamp on top of the vessel
        rect(f, 23, 11, 3, 13, NAVY[1])
        frame(f, 22, 10, 5, 15, OUT)
        box(f, 19, 24, 11, 3, GREEN[1], OUT)
        if ph == 2:
            for wx, wy in ((15, 46), (33, 47)):
                px(f, wx, wy, SKY[0])
        plate2(f, GREEN)
        frames.append(f)
    return back, frames


def s_case():
    back = back2(FOAM, ["b...b", "bb.bb", "bbbbb"])
    rect(back, 6, 14, 9, 12, FOAM[1])               # foam reservoir
    rect(back, 6, 14, 9, 3, FOAM[0])
    frame(back, 5, 13, 11, 14, OUT)
    frames = []
    for ph in range(4):
        f = new(MW, MH)
        for side in (0, 1):
            nx = 7 if side == 0 else 35
            rect(f, nx + 1, 42, 3, 14, STEEL[2])
            frame(f, nx, 41, 5, 16, OUT)
            rect(f, nx - 1, 36, 7, 6, PANEL[1])
            rect(f, nx - 1, 36, 7, 1, PANEL[0])
            rect(f, nx - 1, 40, 7, 1, FOAM[1])
            frame(f, nx - 2, 35, 9, 8, OUT)
            tip = nx + 7 if side == 0 else nx - 3
            rect(f, tip, 38, 2, 2, STEEL[3])
        puffs = (
            (),
            ((16, 38, 1), (31, 39, 1)),
            ((17, 37, 2), (30, 38, 2), (15, 42, 1), (33, 42, 1)),
            ((18, 35, 2), (29, 36, 2), (16, 43, 1), (32, 34, 1)),
        )[ph]
        for cx, cy, r in puffs:
            disc(f, cx, cy, r, FOAM[0])
            px(f, cx, cy, WHITE)
        # casing ring lowered from above
        off = (0, 3, 6, 3)[ph]
        rect(f, 23, 11, 3, 8 + off, STEEL[1])
        frame(f, 22, 10, 5, 10 + off, OUT)
        rect(f, 15, 19 + off, 19, 3, PANEL[0])
        rect(f, 15, 21 + off, 19, 1, PANEL[2])
        frame(f, 14, 18 + off, 21, 5, OUT)
        plate2(f, FOAM)
        frames.append(f)
    return back, frames


def s_ship():
    back = back2(PURPLE, ["..g..", ".g.g.", "g...g"])
    for i in range(4):                               # flat-packed boxes
        rect(back, 6, 24 - i * 3, 10, 2, CARD[1] if i % 2 else CARD[0])
        frame(back, 5, 23 - i * 3, 12, 4, CARD[3])
    frames = []
    for ph in range(4):
        f = new(MW, MH)
        # inspection camera on a post (flashes)
        rect(f, 8, 26, 2, 30, STEEL[1])
        frame(f, 7, 25, 4, 32, OUT)
        box(f, 5, 28, 8, 6, DARKSTEEL, OUT)
        px(f, 12, 31, WHITE_HOT if ph == 1 else SKY[1])
        if ph == 1:
            for dx, dy in ((14, 29), (15, 31), (14, 33)):
                px(f, dx, dy, WHITE_HOT)
        # strapping head
        off = (0, 3, 6, 3)[ph]
        rect(f, 23, 11, 3, 9 + off, STEEL[1])
        frame(f, 22, 10, 5, 11 + off, OUT)
        rect(f, 14, 20 + off, 21, 4, PURPLE[1])
        rect(f, 14, 20 + off, 21, 1, PURPLE[0])
        frame(f, 13, 19 + off, 23, 6, OUT)
        for sx in (17, 30):
            rect(f, sx, 25 + off, 1, 4, NAVY[1])
        # pass lamp
        box(f, 36, 28, 6, 6, GREEN[1] if ph >= 2 else GREEN[3], OUT)
        if ph >= 2:
            px(f, 38, 30, WHITE), px(f, 39, 31, WHITE)
        rect(f, 38, 34, 2, 22, STEEL[1])
        frame(f, 37, 33, 4, 24, OUT)
        plate2(f, PURPLE)
        frames.append(f)
    return back, frames


def make_machines_stainless():
    for name, fn in (("s_prep", s_prep), ("s_laser", s_laser), ("s_form", s_form), ("s_tig", s_tig),
                     ("s_coil", s_coil), ("s_qa", s_qa), ("s_case", s_case), ("s_ship", s_ship)):
        back, frames = fn()
        save(back, "machine_%s_back.png" % name)
        save(strip(frames), "machine_%s_front.png" % name)


# ------------------------------------------------------- worker and lorry
def make_worker_steel():
    pal = {
        "o": OUT, "h": WHITE, "H": PANEL[1], "s": SKIN, "e": OUT, "b": NAVY[1], "B": NAVY[2],
        "w": (250, 220, 110, 255), "k": (70, 52, 44, 255), "t": STEEL[1], "T": STEEL[3], "n": TIMBER[2],
    }
    base = ["....hhhh......", "...hHHhhh.....", "..hhhhhhhh....", "...ssssss.....", "...sesses.....", "...ssssss.....",
            "....ssss......", "..bbwwwwbb....", ".bbbbbbbbbb...", ".sbbwwwwbbs...", ".s.bbbbbb.s...", "...bbbbbb.....",
            "...BBBBBB.....", "...BB..BB.....", "...BB..BB.....", "...kk..kk....."]
    up = ["....hhhh..tt..", "...hHHhhh.tT..", "..hhhhhhhh.n..", "...ssssss..n..", "...sesses.sn..", "...ssssss.s...",
          "....ssss.bb...", "..bbwwwwbb....", ".bbbbbbbbb....", ".sbbwwwwb.....", ".s.bbbbbb.....", "...bbbbbb.....",
          "...BBBBBB.....", "...BB..BB.....", "...BB..BB.....", "...kk..kk....."]
    down = ["..............", "....hhhh......", "...hHHhhh.....", "..hhhhhhhh....", "...ssssss.....", "...sesses.....",
            "...ssssss.....", "..bbwwwwbb....", ".bbbbbbbbbbb..", ".sbbwwwwb.bstt", ".s.bbbbbb.nnTt", "...bbbbbb.....",
            "...BBBBBB.....", "...BB..BB.....", "...BB..BB.....", "...kk..kk....."]
    frames = []
    for rows in (base, up, down):
        img = new(16, 20)
        img.paste(ascii_sprite(rows, pal), (1, 2))
        outline(img)
        rect(img, 3, 19, 9, 1, SHADOW)
        frames.append(img)
    save(strip(frames), "worker_steel.png")


def make_lorry():
    img = new(72, 44)
    rect(img, 3, 39, 66, 4, SHADOW)
    # box trailer
    rect(img, 20, 2, 49, 33, PANEL[1])
    rect(img, 20, 2, 49, 3, PANEL[0])
    rect(img, 20, 31, 49, 4, PANEL[2])
    for x in range(26, 60, 6):
        rect(img, x, 5, 1, 26, PANEL[2])
    rect(img, 61, 5, 8, 29, (48, 44, 58, 255))               # open rear
    rect(img, 62, 16, 6, 18, CARD[2])
    rect(img, 62, 16, 6, 2, CARD[0])
    rect(img, 64, 16, 1, 18, NAVY[1])
    rect(img, 20, 22, 41, 4, NAVY[1])                          # livery stripe
    rect(img, 20, 22, 41, 1, NAVY[0])
    cylinder_body(img, 36, 7, 8, 12, STEEL, top=(2, 1), bottom=(1,))
    frame(img, 19, 1, 51, 35, OUT)
    # cab
    rect(img, 4, 12, 15, 23, NAVY[1])
    rect(img, 4, 12, 15, 2, NAVY[0])
    rect(img, 4, 31, 15, 4, NAVY[2])
    rect(img, 6, 15, 10, 8, SKY[1])
    rect(img, 6, 15, 10, 2, SKY[0])
    line(img, 8, 21, 12, 16, WHITE)
    frame(img, 5, 14, 12, 10, OUT)
    frame(img, 3, 11, 17, 25, OUT)
    rect(img, 2, 28, 2, 3, YELLOW[0])
    rect(img, 1, 33, 4, 2, STEEL[3])
    rect(img, 13, 26, 3, 1, STEEL[0])
    rect(img, 16, 6, 2, 6, STEEL[2])                           # exhaust stack
    frame(img, 15, 5, 4, 7, OUT)
    for wx in (11, 46, 57):
        disc(img, wx, 36, 5, OUT)
        disc(img, wx, 36, 3, (70, 66, 76, 255))
        disc(img, wx, 36, 1, STEEL[0])
    save(img, "lorry.png")


# ------------------------------------------------------------- background
def make_background_stainless():
    rnd = random.Random(11)
    img = new(BG_W, BG_H, EPOXY[1])
    # sealed epoxy floor in big glossy bays
    for y in range(WALL_H, BG_H):
        for x in range(BG_W):
            col = EPOXY[1] if ((x // 74) + ((y - WALL_H) // 68)) % 2 == 0 else EPOXY[0]
            if x % 74 == 0 or (y - WALL_H) % 68 == 0:
                col = EPOXY[2]
            img.putpixel((x, y), col)
    for _ in range(60):   # soft reflections of the lights
        x, y = rnd.randrange(12, BG_W - 30), rnd.randrange(WALL_H + 12, BG_H - 12)
        for i in range(rnd.randrange(6, 16)):
            px(img, x + i, y, (255, 255, 255, 46))

    # green pedestrian walkway between the rows
    wy0, wy1 = 168, 212
    rect(img, 8, wy0, BG_W - 60, wy1 - wy0, (96, 170, 120, 70))
    rect(img, 8, wy0, BG_W - 60, 2, WHITE)
    rect(img, 8, wy1, BG_W - 60, 2, WHITE)
    for x in range(40, BG_W - 80, 64):   # walking-figure arrows
        for i in range(5):
            rect(img, x + i, 188 - i, 1, 1 + 2 * i, (255, 255, 255, 150))
        rect(img, x + 5, 186, 8, 5, (255, 255, 255, 150))

    # dispatch bay hazard hatching (bottom-left)
    for y in range(218, 286):
        for x in range(6, 86):
            if x < 9 or x > 82 or y < 221 or y > 282:
                img.putpixel((x, y), YELLOW[1] if ((x + y) // 4) % 2 == 0 else OUT)
    # coil stock bay marking (top-left)
    frame(img, 8, 96, 56, 54, NAVY[1])
    frame(img, 9, 97, 54, 52, NAVY[0])

    # ---- back wall: white cladding with a blue band
    rect(img, 0, 0, BG_W, 38, WALL[1])
    rect(img, 0, 0, BG_W, 3, WALL[2])
    for x in range(0, BG_W, 37):
        rect(img, x, 3, 1, 35, WALL[2])
        rect(img, x + 1, 3, 1, 35, WALL[0])
    rect(img, 0, 38, BG_W, 2, DARKSTEEL)
    rect(img, 0, 40, BG_W, 14, NAVY[1])
    rect(img, 0, 40, BG_W, 1, NAVY[0])
    rect(img, 0, 50, BG_W, 2, WHITE)
    rect(img, 0, 54, BG_W, 4, DARKSTEEL)
    rect(img, 0, 54, BG_W, 1, STEEL[2])
    rect(img, 0, WALL_H, BG_W, 5, (0, 0, 0, 40))
    rect(img, 0, WALL_H + 5, BG_W, 3, (0, 0, 0, 16))

    # wide steel-framed windows
    for wx in (10, 86, 320, 388):
        box(img, wx, 6, 46, 28, STEEL[2], OUT)
        rect(img, wx + 2, 8, 42, 24, SKY[1])
        rect(img, wx + 2, 8, 42, 9, SKY[0])
        rect(img, wx + 6, 12, 10, 2, WHITE), rect(img, wx + 8, 11, 6, 1, WHITE)
        rect(img, wx + 28, 21, 9, 2, WHITE), rect(img, wx + 30, 20, 5, 1, WHITE)
        for mx in (15, 30):
            rect(img, wx + mx, 8, 1, 24, STEEL[2])
        rect(img, wx + 2, 8, 42, 1, (120, 170, 200, 255))
        line(img, wx + 4, 30, wx + 12, 10, (255, 255, 255, 90))
        rect(img, wx - 1, 34, 48, 2, STEEL[1])
        frame(img, wx - 2, 33, 50, 4, OUT)

    # brushed-steel company sign (the factory name is drawn on it in game)
    label = "COPPERTOP CYLINDER WORKS"
    tw = text_width(label)
    sx = (BG_W - tw) // 2 - 6
    box(img, sx, 5, tw + 12, 17, STEEL[1], OUT)
    rect(img, sx + 1, 6, tw + 10, 1, STEEL[0])
    rect(img, sx + 3, 8, tw + 6, 11, (52, 66, 84, 255))
    frame(img, sx + 2, 7, tw + 8, 13, STEEL[3])
    for bx in (sx + 1, sx + tw + 10):
        px(img, bx, 7, WHITE), px(img, bx, 19, WHITE)
    sub = "STAINLESS DIVISION"
    text(img, (BG_W - text_width(sub)) // 2, 25, sub, (120, 136, 156, 255))

    # digital production board
    box(img, 140, 40, 60, 13, SCREEN, OUT)
    text(img, 143, 43, "LINE OK", (120, 240, 150, 255))
    for i, hgt in enumerate((3, 5, 4, 7, 6)):
        rect(img, 186 + i * 2, 51 - hgt, 1, hgt, ARC)
    # first-aid box + emergency stop
    box(img, 250, 41, 11, 11, WHITE, OUT)
    rect(img, 254, 43, 3, 7, GREEN[1]), rect(img, 252, 45, 7, 3, GREEN[1])
    box(img, 268, 42, 9, 9, YELLOW[1], OUT)
    disc(img, 272, 46, 2, RED[1])
    # stainless pipe run with blue valves
    rect(img, 0, 45, 136, 3, STEEL[1]), rect(img, 0, 45, 136, 1, STEEL[0])
    rect(img, 282, 45, BG_W - 282, 3, STEEL[1]), rect(img, 282, 45, BG_W - 282, 1, STEEL[0])
    for vx in (60, 330):
        box(img, vx, 42, 7, 8, NAVY[0], OUT)
        rect(img, vx + 2, 39, 3, 3, STEEL[2])
        frame(img, vx, 38, 7, 3, OUT)
    # fire extinguisher
    rect(img, 433, 34, 6, 16, RED[1]), rect(img, 433, 34, 2, 16, RED[0])
    frame(img, 432, 33, 8, 18, OUT)
    rect(img, 434, 30, 4, 3, STEEL[3]), rect(img, 434, 40, 4, 3, WHITE)

    # ---- floor props
    def coil(cx, cy, r):
        rect(img, cx - r, cy + r - 1, 2 * r, 3, (0, 0, 0, 50))
        disc(img, cx, cy, r, OUT)
        disc(img, cx, cy, r - 1, STEEL[1])
        disc(img, cx, cy, r - 3, STEEL[2])
        disc(img, cx, cy, r - 5, STEEL[1])
        disc(img, cx, cy, max(2, r - 8), DARKSTEEL)
        for a, b in ((-r + 3, -3), (-r + 4, -5)):
            px(img, cx + a, cy + b, WHITE)
        line(img, cx - 2, cy - r + 2, cx + 3, cy - r + 2, WHITE)

    # coil cradle (timber chocks) with stainless coils
    rect(img, 12, 138, 48, 6, TIMBER[1]), rect(img, 12, 138, 48, 2, TIMBER[0])
    frame(img, 11, 137, 50, 8, OUT)
    rect(img, 11, 145, 50, 2, (0, 0, 0, 50))
    coil(24, 126, 12)
    coil(47, 126, 12)
    coil(36, 108, 11)

    # QA bench with monitor and microscope
    tx, ty = 96, 180
    rect(img, tx, ty, 40, 8, PANEL[0]), rect(img, tx, ty + 8, 40, 4, PANEL[2])
    frame(img, tx - 1, ty - 1, 42, 14, OUT)
    rect(img, tx + 1, ty + 13, 3, 8, STEEL[3]), rect(img, tx + 36, ty + 13, 3, 8, STEEL[3])
    rect(img, tx - 1, ty + 21, 42, 2, (0, 0, 0, 40))
    box(img, tx + 4, ty - 10, 14, 10, SCREEN, OUT)
    line(img, tx + 6, ty - 4, tx + 9, ty - 7, (120, 240, 150, 255))
    line(img, tx + 9, ty - 7, tx + 12, ty - 5, (120, 240, 150, 255))
    line(img, tx + 12, ty - 5, tx + 15, ty - 8, (120, 240, 150, 255))
    rect(img, tx + 10, ty, 2, 2, DARKSTEEL)
    box(img, tx + 24, ty - 7, 4, 8, DARKSTEEL, OUT)            # microscope
    rect(img, tx + 22, ty - 1, 9, 2, STEEL[1])
    box(img, tx + 32, ty - 2, 5, 5, WHITE, OUT)                # tea mug: still a British factory
    rect(img, tx + 33, ty - 1, 3, 1, (120, 80, 50, 255))

    # forklift parked in the aisle
    fx, fy = 300, 172
    rect(img, fx + 2, fy + 22, 30, 3, (0, 0, 0, 50))
    box(img, fx + 8, fy + 6, 20, 15, YELLOW[1], OUT)
    rect(img, fx + 9, fy + 7, 18, 2, YELLOW[0])
    rect(img, fx + 9, fy + 17, 18, 3, YELLOW[2])
    frame(img, fx + 11, fy - 2, 13, 9, OUT)                    # roll cage
    rect(img, fx + 12, fy - 1, 11, 2, DARKSTEEL)
    box(img, fx + 14, fy + 9, 7, 6, DARKSTEEL, OUT)            # seat
    rect(img, fx + 4, fy - 3, 2, 25, STEEL[2])                 # mast
    frame(img, fx + 3, fy - 4, 4, 27, OUT)
    rect(img, fx - 5, fy + 19, 10, 2, STEEL[1])                # forks
    frame(img, fx - 6, fy + 18, 12, 4, OUT)
    for wx in (fx + 12, fx + 24):
        disc(img, wx, fy + 21, 3, OUT)
        disc(img, wx, fy + 21, 1, STEEL[1])

    # tool trolley
    box(img, 196, 180, 18, 14, RED[1], OUT)
    rect(img, 197, 181, 16, 2, RED[0])
    for dy in (185, 189):
        rect(img, 198, dy, 14, 1, RED[3])
        rect(img, 203, dy + 1, 4, 1, STEEL[0])
    rect(img, 196, 194, 18, 2, (0, 0, 0, 50))

    # palletised finished goods along the bottom
    for i in range(4):
        bx = 290 + i * 17
        box(img, bx, 296, 15, 16, CARD[1], OUT)
        rect(img, bx + 1, 297, 13, 3, CARD[0])
        rect(img, bx + 3, 297, 1, 14, NAVY[1]), rect(img, bx + 11, 297, 1, 14, NAVY[1])
        rect(img, bx, 312, 15, 2, (0, 0, 0, 50))
    rect(img, 288, 312, 72, 3, TIMBER[2])
    frame(img, 287, 311, 74, 5, OUT)

    # steel drum + plants
    for dx in (232, 248):
        box(img, dx, 296, 12, 16, NAVY[1], OUT)
        rect(img, dx + 1, 297, 3, 14, NAVY[0])
        rect(img, dx + 1, 301, 10, 1, NAVY[3]), rect(img, dx + 1, 307, 10, 1, NAVY[3])
        rect(img, dx, 312, 12, 2, (0, 0, 0, 50))

    def plant(x, y):
        rect(img, x + 2, y + 10, 8, 7, PANEL[1])
        rect(img, x + 1, y + 9, 10, 2, PANEL[0])
        frame(img, x, y + 8, 12, 10, OUT)
        for lx, ly, c in ((5, 0, GREEN[0]), (3, 2, GREEN[1]), (7, 2, GREEN[1]), (1, 4, GREEN[2]), (5, 3, GREEN[0]),
                          (9, 4, GREEN[2]), (3, 5, GREEN[1]), (7, 5, GREEN[1])):
            frame(img, x + lx - 1, y + ly - 1, 5, 6, OUT)
            rect(img, x + lx, y + ly, 3, 4, c)
        rect(img, x, y + 18, 12, 2, (0, 0, 0, 50))

    plant(424, 268)
    plant(424, 62)

    # corrugated steel side and bottom walls
    for x in range(0, 5):
        for y in range(WALL_H, BG_H):
            c = STEEL[2] if (y // 3) % 2 else STEEL[1]
            img.putpixel((x, y), c)
            img.putpixel((BG_W - 1 - x, y), c)
    rect(img, 5, WALL_H, 1, BG_H - WALL_H, OUT)
    rect(img, BG_W - 6, WALL_H, 1, BG_H - WALL_H, OUT)
    for y in range(BG_H - 5, BG_H):
        for x in range(BG_W):
            img.putpixel((x, y), STEEL[2] if (x // 3) % 2 else STEEL[1])
    rect(img, 0, BG_H - 6, BG_W, 1, OUT)
    rect(img, 0, 226, 5, 52, (40, 34, 44, 255))                # loading door
    rect(img, 0, 224, 6, 2, YELLOW[1]), rect(img, 0, 278, 6, 2, YELLOW[1])
    save(img, "factory_bg_stainless.png")


# ------------------------------------------------------------- thumbnails
def make_thumbnails():
    # copper works: a brick workshop with a pitched roof
    img = new(64, 44)
    rect(img, 0, 36, 64, 8, (120, 150, 96, 255))
    rect(img, 0, 36, 64, 1, (150, 180, 116, 255))
    rect(img, 6, 16, 52, 22, (176, 96, 76, 255))
    for y in range(17, 38, 3):
        for x in range(6 + (y % 2) * 3, 58, 6):
            px(img, x, y, (140, 72, 60, 255))
    for i in range(10):                                         # roof
        rect(img, 4 + i, 15 - i, 56 - 2 * i, 1, (96, 78, 84, 255) if i % 2 else (116, 96, 100, 255))
    frame(img, 5, 15, 54, 23, OUT)
    box(img, 44, 2, 6, 10, (140, 72, 60, 255), OUT)             # chimney
    px(img, 46, 0, WHITE), px(img, 48, -1 + 1, WHITE)
    box(img, 12, 22, 9, 8, SKY[1], OUT), box(img, 43, 22, 9, 8, SKY[1], OUT)
    box(img, 27, 24, 10, 14, TIMBER[2], OUT)
    box(img, 17, 17, 30, 5, TIMBER[2], OUT)
    rect(img, 19, 19, 26, 1, COPPER[0])
    spr = new(8, 10)
    cylinder_body(spr, 1, 1, 6, 8, COPPER, top=(1,), bottom=(0,))
    outline(spr)
    img.alpha_composite(spr, (28, 27))
    save(img, "factory_thumb_copper.png")

    # stainless plant: a long, modern steel-clad building
    img = new(64, 44)
    rect(img, 0, 36, 64, 8, (120, 150, 96, 255))
    rect(img, 0, 36, 64, 1, (150, 180, 116, 255))
    rect(img, 2, 12, 60, 26, PANEL[1])
    for x in range(4, 62, 3):
        rect(img, x, 13, 1, 24, PANEL[2])
    rect(img, 2, 12, 60, 2, PANEL[0])
    rect(img, 2, 18, 60, 4, NAVY[1])
    rect(img, 2, 18, 60, 1, NAVY[0])
    frame(img, 1, 11, 62, 28, OUT)
    for wx in (6, 18, 40, 52):
        box(img, wx, 24, 8, 6, SKY[1], OUT)
        rect(img, wx + 1, 25, 6, 2, SKY[0])
    box(img, 28, 26, 9, 12, DARKSTEEL, OUT)
    for y in range(28, 37, 2):
        rect(img, 29, y, 7, 1, STEEL[2])
    box(img, 48, 2, 8, 10, STEEL[1], OUT)                       # silo
    rect(img, 49, 3, 2, 8, STEEL[0])
    box(img, 8, 6, 5, 6, STEEL[2], OUT)
    spr = new(8, 11)
    cylinder_body(spr, 1, 1, 6, 9, STEEL, top=(1,), bottom=(0,))
    outline(spr)
    img.alpha_composite(spr, (22, 0))
    save(img, "factory_thumb_stainless.png")

    # HUD "factories" icon (12x12)
    icon = [
        "........oo..",
        "........o#o.",
        "........o#o.",
        "o.o.o...o#o.",
        "o#o#o#ooo#o.",
        "o#########o.",
        "o#########o.",
        "o#o#o#o#o#o.",
        "o#########o.",
        "o###ooo###o.",
        "o###o.o###o.",
        "ooooo.ooooo.",
    ]
    save(ascii_sprite(icon, {"o": OUT, "#": CREAM[0]}), "factories_icon.png")
    # padlock for locked factories (10x12)
    lock = [
        "..oooooo..",
        ".o######o.",
        ".o#oooo#o.",
        ".o#o..o#o.",
        "oooooooooo",
        "o11111111o",
        "o111oo111o",
        "o111oo111o",
        "o1111o111o",
        "o11111111o",
        "o22222222o",
        "oooooooooo",
    ]
    save(ascii_sprite(lock, {"o": OUT, "#": STEEL[1], "1": GOLD[1], "2": GOLD[2]}), "padlock.png")


def main():
    make_items_stainless()
    make_machines_stainless()
    make_worker_steel()
    make_lorry()
    make_background_stainless()
    make_thumbnails()
    print("stainless art generated in", os.path.normpath(OUT_DIR))


if __name__ == "__main__":
    main()

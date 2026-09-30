"""Card 06 gets card 05's RARE border (owner, 2026-10-01: "the two rare cards' borders differ,
make 06 follow 05 exactly"). Pure Pillow, no image model.

The v3 cards 05 and 06 were generated one by one, so each got its own take on the silver holo
frame: 06 had a louder rainbow band, tighter top corners (r 26-28 against 05's 31.5), a rounder
bottom-left corner (r 41), a SERIES box that sits on the frame as a separate box and a RARE tag
24 px higher. This script keeps everything of 06 that is inside 05's artwork panel (TiTi, props,
mint background, logo, title, tagline) and takes everything outside it from 05 (the frame, the
SERIES notch, the RARE tag), then puts 06's number into 05's notch:

  1. PANEL: 05's artwork panel as an analytic shape, measured on design/cards_v3/c5.jpg where the
     rim starts to tint the cream panel (pixel-centre coordinates):
       rounded rectangle x 25.4..741.8, y 23.4..1127.6, corner radius 31.5
       minus the RARE tag   x 634.6.., y 955.3..995.8, left corners r 7 (its right end runs into the frame)
       minus the SERIES notch x 617.5.., y 1003.3.., top-left corner r 34 (concave for the panel)
       and the panel's own rounded corner r 46 where its bottom edge meets the notch.
     Drawn 8x supersampled and box-filtered down, so the mask edge is anti-aliased.
  2. CLEAN: 06's own panel (x 23.75..742.1, y 24.75..1125.25; corners r 27.7 / 26 / 41; its box
     from x 621.5 / y 980.5 with a r 46 corner at the bottom) shrunk by 2 px, minus 06's RARE
     tag (x 636-727, y 931-971) and SERIES box, grown by 3 px. Every pixel of 05's panel that is not
     clean in 06 (06's old tag and box, and the thin strips where 05's panel reaches past 06's:
     2 px at the top, 2-3 px at the bottom, the bottom-left corner) is repainted by a harmonic
     (Laplace) fill from the clean mint pixels around it, so no box outline or edge is left.
  3. NUMBER: in 05's notch the "05" and the red underline are lifted out (harmonic fill of the
     pale holo around them). "06" is cut from 06's own SERIES box as an ink matte (darkness
     against its locally filled background), scaled to the height of 05's "05" and set on the
     same centre and baseline, in 05's ink. The underline keeps 05's exact shape and position (its
     matte against the filled background) in 06's green.
  4. out = 05 outside the panel, repaired 06 inside it, through the anti-aliased panel mask.

  python tool/art_c6_frame.py              # design/cards_v3/c6.jpg + assets/cards/c6.jpg + sheets
  python tool/art_c6_frame.py --debug DIR  # also write the masks and 3x seam crops into DIR

Source images: design/cards_v3/c5.jpg and design/cards_v3/c6_prev.jpg (the previous 06, copied
there on the first run), so re-running never compounds.
"""
import os, shutil, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(ROOT)
DST = os.path.join(REPO, 'design', 'cards_v3')
LIVE = os.path.join(REPO, 'assets', 'cards', 'c6.jpg')
W, H = 768, 1152
SS = 8  # mask supersampling

# 05's panel (pixel-centre coordinates of the first rim-tinted position; see the docstring)
PANEL = dict(L=25.4, T=23.4, R=741.8, B=1127.6, r=31.5)
TAG = dict(L=634.6, T=955.3, B=995.8, r=7.0)
NOTCH = dict(L=617.5, T=1003.3, r=34.0)
FILLET = 46.0
GROW = 0.3  # the panel reaches this far into the rim's soft onset, so no cream line is left

# 06's own panel, tag and box (to know which of its pixels are clean mint background)
P6 = dict(L=23.75, T=24.75, R=742.1, B=1125.25, tl=27.7, tr=26.0, bl=41.0)
TAG6 = (636.25, 931.25, 727.25, 970.75)
BOX6 = dict(L=621.5, T=980.5, r=22.0, fillet=46.0)

# number boxes (integer pixel windows)
NUM5 = (640, 1047, 736, 1104)      # "05" in 05's notch (SERIES label ends at y 1045)
LINE5 = (648, 1102, 728, 1119)     # 05's red underline
NUM6 = (640, 1023, 736, 1084)      # "06" in 06's box
LINE6 = (648, 1086, 726, 1102)     # 06's green underline


# ---------------------------------------------------------------- masks

def _X(u):
    return (u + 0.5) * SS


def rrect(d, box, radii, fill, bg):
    """A rectangle with its own radius per corner (tl, tr, br, bl), in pixel-centre coordinates,
    on the SS-times canvas. Corners: clear the corner square to bg, then draw the quarter disc."""
    x0, y0, x1, y1 = (_X(v) for v in box)
    d.rectangle((x0, y0, x1, y1), fill=fill)
    for i, r in enumerate(radii):
        if r <= 0:
            continue
        R = r * SS
        if i == 0:
            sq, bb, a = (x0, y0, x0 + R, y0 + R), (x0, y0, x0 + 2 * R, y0 + 2 * R), (180, 270)
        elif i == 1:
            sq, bb, a = (x1 - R, y0, x1, y0 + R), (x1 - 2 * R, y0, x1, y0 + 2 * R), (270, 360)
        elif i == 2:
            sq, bb, a = (x1 - R, y1 - R, x1, y1), (x1 - 2 * R, y1 - 2 * R, x1, y1), (0, 90)
        else:
            sq, bb, a = (x0, y1 - R, x0 + R, y1), (x0, y1 - 2 * R, x0 + 2 * R, y1), (90, 180)
        d.rectangle(sq, fill=bg)
        d.pieslice(bb, a[0], a[1], fill=fill)


def convex_corner(d, cx, cy, r, fill, bg):
    """Round off a bottom-right panel corner at (cx, cy) with radius r (the corner where the panel's
    bottom edge meets the SERIES notch)."""
    x1, y1, R = _X(cx), _X(cy), r * SS
    d.rectangle((x1 - R, y1 - R, x1, y1), fill=bg)
    d.pieslice((x1 - 2 * R, y1 - 2 * R, x1, y1), 0, 90, fill=fill)


def down(canvas):
    return canvas.resize((W, H), Image.BOX)


def panel_mask(g=GROW):
    """05's artwork panel, 255 inside, anti-aliased."""
    c = Image.new('L', (W * SS, H * SS), 0)
    d = ImageDraw.Draw(c)
    p, t, n = PANEL, TAG, NOTCH
    rrect(d, (p['L'] - g, p['T'] - g, p['R'] + g, p['B'] + g), (p['r'] + g, p['r'] + g, 0, p['r'] + g), 255, 0)
    rrect(d, (t['L'] + g, t['T'] + g, W + 40, t['B'] - g), (t['r'] - g, 0, 0, t['r'] - g), 0, 255)
    rrect(d, (n['L'] + g, n['T'] + g, W + 40, H + 40), (n['r'] - g, 0, 0, 0), 0, 255)
    convex_corner(d, n['L'] + g, p['B'] + g, FILLET + g, 255, 0)
    return down(c)


def clean6_mask(erode=2.0, grow=3.0):
    """06's pixels that are plain panel (mint background or artwork), 255 = clean."""
    c = Image.new('L', (W * SS, H * SS), 0)
    d = ImageDraw.Draw(c)
    p, b, e = P6, BOX6, erode
    rrect(d, (p['L'] + e, p['T'] + e, p['R'] - e, p['B'] - e), (p['tl'] - e, p['tr'] - e, 0, p['bl'] - e), 255, 0)
    rrect(d, (TAG6[0] - grow, TAG6[1] - grow, TAG6[2] + grow, TAG6[3] + grow), (8 + grow,) * 4, 0, 255)
    rrect(d, (b['L'] - grow, b['T'] - grow, W + 40, H + 40), (b['r'] + grow, 0, 0, 0), 0, 255)
    convex_corner(d, b['L'] - grow, p['B'] - e, b['fillet'] - grow, 255, 0)
    m = down(c)
    return m.point(lambda v: 255 if v >= 250 else 0)


# ---------------------------------------------------------------- harmonic fill

def harmonic_fill(im, fill, known, iters=250, omega=1.85):
    """Repaint the pixels where `fill` is set by solving Laplace's equation from the `known`
    pixels around them (4-neighbours; neighbours that are neither are left out, a free edge).
    Starts from an onion-peel fill, then SOR. Returns a new RGB image."""
    w, h = im.size
    src = im.load()
    fp, kp = fill.load(), known.load()
    todo = [(x, y) for y in range(h) for x in range(w) if fp[x, y] and not kp[x, y]]
    if not todo:
        return im.copy()
    idx = {q: i for i, q in enumerate(todo)}
    val = [None] * len(todo)
    # onion peel: repeatedly average the already-known 8-neighbours
    got = [False] * len(todo)

    def known_at(x, y):
        return 0 <= x < w and 0 <= y < h and kp[x, y]

    def nb8(x, y):
        return ((x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy)

    ring = {i for i, (x, y) in enumerate(todo) if any(known_at(a, b) for a, b in nb8(x, y))}
    left = set(range(len(todo)))
    while ring:
        layer, ring = sorted(ring), set()
        newly = []
        for i in layer:
            x, y = todo[i]
            acc, n = [0.0, 0.0, 0.0], 0
            for a, b in nb8(x, y):
                if known_at(a, b):
                    c = src[a, b]
                elif (a, b) in idx and got[idx[(a, b)]]:
                    c = val[idx[(a, b)]]
                else:
                    continue
                acc[0] += c[0]; acc[1] += c[1]; acc[2] += c[2]; n += 1
            if n:
                newly.append((i, [v / n for v in acc]))
        for i, v in newly:
            val[i], got[i] = v, True
            left.discard(i)
        for i, _ in newly:
            x, y = todo[i]
            for a, b in nb8(x, y):
                j = idx.get((a, b))
                if j is not None and not got[j]:
                    ring.add(j)
    for i in left:  # unreachable (should not happen): leave the source pixel
        val[i] = list(src[todo[i]])
    # neighbour lists: ('k', rgb) fixed or ('f', index)
    nbs = []
    for (x, y) in todo:
        lst = []
        for a, b in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if known_at(a, b):
                lst.append((None, src[a, b]))
            elif (a, b) in idx:
                lst.append((idx[(a, b)], None))
        nbs.append(lst)
    for _ in range(iters):
        for i, lst in enumerate(nbs):
            if not lst:
                continue
            s0 = s1 = s2 = 0.0
            for j, c in lst:
                if j is not None:
                    c = val[j]
                s0 += c[0]; s1 += c[1]; s2 += c[2]
            n = len(lst)
            v = val[i]
            v[0] += omega * (s0 / n - v[0]); v[1] += omega * (s1 / n - v[1]); v[2] += omega * (s2 / n - v[2])
    out = im.copy()
    op = out.load()
    for (x, y), v in zip(todo, val):
        op[x, y] = tuple(max(0, min(255, round(c))) for c in v)
    return out


# ---------------------------------------------------------------- the number

def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def window_masks(im, box, test, grow=2):
    """Inside box: the pixels passing test (ink), grown by `grow` px -> (fill, known) masks for the
    harmonic fill of the background under them; known = the rest of the window."""
    ink = Image.new('L', im.size, 0)
    p, q = im.load(), ink.load()
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        for x in range(x0, x1):
            if test(p[x, y]):
                q[x, y] = 255
    fill = ink.filter(ImageFilter.MaxFilter(2 * grow + 1))
    known = Image.new('L', im.size, 0)
    ImageDraw.Draw(known).rectangle((x0, y0, x1 - 1, y1 - 1), fill=255)
    known.paste(0, (0, 0), fill)
    return fill, known


def matte(im, bg, box, channel, ink_value):
    """Ink coverage inside box: how far each pixel's channel value has moved from the filled
    background toward the ink value. Returns an 'L' image the size of box."""
    x0, y0, x1, y1 = box
    p, b = im.load(), bg.load()
    m = Image.new('L', (x1 - x0, y1 - y0), 0)
    mp = m.load()
    for y in range(y0, y1):
        for x in range(x0, x1):
            v, vb = channel(p[x, y]), channel(b[x, y])
            a = (vb - v) / max(1.0, vb - ink_value)
            mp[x - x0, y - y0] = max(0, min(255, round(255 * a)))
    return m


def bbox_of(m, thr=128):
    return m.point(lambda v: 255 if v >= thr else 0).getbbox()


def put_number(c5, c6, debug=None):
    """05's notch with 06's number: returns the edited copy of c5."""
    dark = lambda c: lum(c) < 150
    red = lambda c: c[0] - c[1] > 60 and c[0] > 120
    green = lambda c: c[1] - c[0] > 30 and lum(c) < 170

    # 05: lift the "05" and the red line out of the notch
    f1, k1 = window_masks(c5, NUM5, dark)
    f2, k2 = window_masks(c5, LINE5, red)
    fill5 = Image.new('L', c5.size, 0)
    fill5.paste(255, (0, 0), f1); fill5.paste(255, (0, 0), f2)
    known5 = Image.new('L', c5.size, 0)
    known5.paste(255, (0, 0), k1); known5.paste(255, (0, 0), k2)
    known5.paste(0, (0, 0), fill5)
    bg5 = harmonic_fill(c5, fill5, known5)
    m05 = matte(c5, bg5, NUM5, lum, 8)
    mline = matte(c5, bg5, LINE5, lambda c: c[1], 30)

    # 06: its "06" as a matte against its own filled box background
    f6, k6 = window_masks(c6, NUM6, dark)
    g6, gk6 = window_masks(c6, LINE6, green)
    bg6 = harmonic_fill(c6, f6, k6)
    m06 = matte(c6, bg6, NUM6, lum, 8)
    bgl6 = harmonic_fill(c6, g6, gk6)

    # colours: 05's ink, 06's green (the solid core of each)
    def core(im, box, m, thr=235):
        x0, y0 = box[:2]
        p, mp = im.load(), m.load()
        px = [p[x0 + x, y0 + y] for y in range(m.height) for x in range(m.width) if mp[x, y] >= thr]
        return tuple(sorted(c[i] for c in px)[len(px) // 2] for i in range(3))
    ink = core(c5, NUM5, m05)
    mg = matte(c6, bgl6, LINE6, lambda c: c[0], 20)
    green_ink = core(c6, LINE6, mg, 200)

    # "06" scaled to the "05" height, same centre x and baseline
    b5, b6 = bbox_of(m05), bbox_of(m06)
    h5, h6 = b5[3] - b5[1], b6[3] - b6[1]
    s = h5 / h6
    cx5 = NUM5[0] + (b5[0] + b5[2]) / 2
    cx6 = NUM6[0] + (b6[0] + b6[2]) / 2
    base5, base6 = NUM5[1] + b5[3], NUM6[1] + b6[3]
    # full-card matte of 06, then the affine map card(05 place) -> card(06 place)
    full6 = Image.new('L', c6.size, 0)
    full6.paste(m06, NUM6[:2])
    a, e = 1 / s, 1 / s
    c = cx6 - cx5 / s
    f = base6 - base5 / s
    placed = full6.transform(c6.size, Image.AFFINE, (a, 0, c, 0, e, f), resample=Image.BICUBIC)

    out = bg5.copy()
    out.paste(ink, (0, 0), placed)
    full_line = Image.new('L', c5.size, 0)
    full_line.paste(mline, LINE5[:2])
    out.paste(green_ink, (0, 0), full_line)
    info = dict(ink05=ink, green06=green_ink, bbox05=(NUM5[0] + b5[0], NUM5[1] + b5[1], NUM5[0] + b5[2], NUM5[1] + b5[3]),
                bbox06=(NUM6[0] + b6[0], NUM6[1] + b6[1], NUM6[0] + b6[2], NUM6[1] + b6[3]), scale=round(s, 4),
                line05=tuple(LINE5[i % 2] + v for i, v in enumerate(bbox_of(mline))))
    if debug:
        bg5.crop((600, 1000, 768, 1140)).resize((504, 420), Image.NEAREST).save(os.path.join(debug, 'num_bg05.png'))
        m06.resize((m06.width * 4, m06.height * 4), Image.NEAREST).save(os.path.join(debug, 'num_matte06.png'))
    return out, info


# ---------------------------------------------------------------- build

def build(debug=None):
    c5 = Image.open(os.path.join(DST, 'c5.jpg')).convert('RGB')
    prev = os.path.join(DST, 'c6_prev.jpg')
    if not os.path.exists(prev):
        shutil.copyfile(os.path.join(DST, 'c6.jpg'), prev)
    c6 = Image.open(prev).convert('RGB')
    assert c5.size == c6.size == (W, H)

    panel = panel_mask()
    clean = clean6_mask()
    # repaint every pixel of 06 that 05's panel shows but that is not clean 06 panel
    need = panel.point(lambda v: 255 if v > 0 else 0).filter(ImageFilter.MaxFilter(3))
    c6r = harmonic_fill(c6, need, clean)

    frame, info = put_number(c5, c6, debug)
    out = Image.composite(c6r, frame, panel)

    dst = os.path.join(DST, 'c6.jpg')
    out.save(dst, quality=86, optimize=True, progressive=True)
    shutil.copyfile(dst, LIVE)
    print('wrote', os.path.relpath(dst, REPO), 'and', os.path.relpath(LIVE, REPO), os.path.getsize(dst), 'bytes')
    print('number:', info)
    if debug:
        panel.save(os.path.join(debug, 'mask_panel05.png'))
        clean.save(os.path.join(debug, 'mask_clean06.png'))
        c6r.save(os.path.join(debug, 'c6_repaired.png'))
    return out


def frames_sheet():
    """design/cards_v3/c5_c6_frames.jpg: 05 and the new 06 side by side, full size, with 2x crops
    of the bottom-right corner and a top corner under each."""
    c5 = Image.open(os.path.join(DST, 'c5.jpg')).convert('RGB')
    c6 = Image.open(os.path.join(DST, 'c6.jpg')).convert('RGB')
    pad, gap, top = 48, 48, 120
    crop_br, crop_tl = (560, 920, 768, 1152), (0, 0, 104, 116)
    zb = [(crop_br[2] - crop_br[0]) * 2, (crop_br[3] - crop_br[1]) * 2]
    zt = [(crop_tl[2] - crop_tl[0]) * 2, (crop_tl[3] - crop_tl[1]) * 2]
    sheet_w = pad * 2 + 2 * W + gap
    sheet_h = top + H + 60 + zb[1] + 60 + pad
    im = Image.new('RGB', (sheet_w, sheet_h), (246, 246, 246))
    d = ImageDraw.Draw(im)

    def font(name, size):
        try:
            return ImageFont.truetype('C:/Windows/Fonts/' + name, size)
        except OSError:
            return ImageFont.load_default()
    d.text((pad, 34), 'Rare cards 05 and 06: one border', font=font('seguibl.ttf', 40), fill=(20, 20, 20))
    d.text((pad, 84), '06 now uses 05\'s silver frame, SERIES notch and RARE tag; its artwork, number and green line are its own',
           font=font('segoeui.ttf', 22), fill=(110, 110, 110))
    for i, (card, lab) in enumerate(((c5, '05  Waiting for the Meet'), (c6, '06  Helping on the Road (new frame)'))):
        x = pad + i * (W + gap)
        im.paste(card, (x, top))
        d.rectangle((x - 1, top - 1, x + W, top + H), outline=(215, 215, 215))
        y = top + H + 14
        d.text((x, y), lab, font=font('segoeuib.ttf', 24), fill=(20, 20, 20))
        y += 46
        im.paste(card.crop(crop_tl).resize(zt, Image.LANCZOS), (x, y))
        im.paste(card.crop(crop_br).resize(zb, Image.LANCZOS), (x + W - zb[0], y))
        d.text((x, y + zt[1] + 8), 'top-left corner, 2x', font=font('segoeui.ttf', 18), fill=(110, 110, 110))
        d.text((x + W - zb[0], y + zb[1] + 8), 'RARE tag and SERIES notch, 2x', font=font('segoeui.ttf', 18), fill=(110, 110, 110))
    dst = os.path.join(DST, 'c5_c6_frames.jpg')
    im = im.crop((0, 0, sheet_w, sheet_h - pad + 40))
    im.save(dst, quality=88, optimize=True, progressive=True)
    print('sheet', os.path.relpath(dst, REPO), im.size, os.path.getsize(dst), 'bytes')


if __name__ == '__main__':
    args = sys.argv[1:]
    debug = args[args.index('--debug') + 1] if '--debug' in args else None
    if debug:
        os.makedirs(debug, exist_ok=True)
    build(debug)
    frames_sheet()
    sys.path.insert(0, ROOT)
    import art_cards_v3
    art_cards_v3.sheets()  # lineup.jpg (and compare.jpg) with the new 06

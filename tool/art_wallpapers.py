"""Chat wallpapers: three backgrounds for the message list, each with a light and a dark variant.

  python tool/art_wallpapers.py

writes assets/wallpapers/<id>_<light|dark>.webp and a preview sheet for the owner at
design/wallpapers/sheet.jpg (each wallpaper with mock bubbles, light and dark).

  ttspot  seamless doodle tile of car-culture Phosphor glyphs, very low contrast.
          Repeats in the app (ImageRepeat.repeat, 768 px tile shown at 384 logical px).
  night   full-screen dusk / night-drive gradient with faint lane lines and city bokeh.
          Not a tile: BoxFit.cover, pinned to the bottom of the list.
  titi    (the default) seamless pastel tile of faded TiTi heads and line cones. Repeats like ttspot.

The bubble / chip colours drawn in the sheet mirror ChatWallpaperStyle in
lib/features/social/presentation/widgets/chat_wallpaper.dart; change both together.
Pillow only (no numpy). Deterministic: every run gives the same files.
"""
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'wallpapers')
DESIGN = os.path.join(ROOT, 'design', 'wallpapers')
PHOSPHOR = os.path.join(ROOT, 'assets', 'fonts', 'Phosphor.ttf')

TILE = 768          # px; the app shows it at scale 2 (384 logical px, about one phone width)
SS = 3              # supersampling for the line art
NIGHT_W, NIGHT_H = 720, 1600   # 9:20, so BoxFit.cover always fits the width on a phone

# Phosphor regular codepoints (@phosphor-icons/web 2.1 style.css). All present in assets/fonts/Phosphor.ttf.
G = dict(
    car=0xe112, car_profile=0xe8cc, steering=0xe9ac, cone=0xe9a8, flag=0xea38, tire=0xedd2, wrench=0xe5d4,
    gas=0xe768, pin=0xe316, coffee=0xe1c2, gauge=0xe628, speedo=0xee74, key=0xe2d6, engine=0xea80, road=0xe838,
    moto=0xe80a, lightning=0xe2de, trophy=0xe67e, camera=0xe10e, headlights=0xe6fe, battery=0xee30,
    signal=0xe9aa, sign=0xe67a, gear=0xe272, ticket=0xe490, sparkle=0xe6a2, star=0xe46a, music=0xe340,
    jeep=0xe2d4, van=0xe826, heart=0xe2a8, drop=0xe210,
)

# The doodle mix: (glyph, weight). Cars, cones and wheels show up most.
DOODLES = [
    ('car', 4), ('car_profile', 4), ('steering', 3), ('cone', 4), ('flag', 3), ('tire', 3), ('wrench', 3),
    ('gas', 3), ('pin', 3), ('coffee', 3), ('speedo', 3), ('gauge', 2), ('key', 3), ('engine', 2), ('road', 2),
    ('moto', 2), ('lightning', 2), ('trophy', 2), ('camera', 2), ('headlights', 2), ('battery', 2),
    ('signal', 2), ('sign', 1), ('gear', 2), ('ticket', 1), ('jeep', 1), ('van', 1), ('music', 1), ('drop', 1),
]

# ------------------------------------------------------------------ colours ---
# Wallpaper grounds.
TT_LIGHT_BASE = (237, 233, 227)     # warm off-white, a step under white so white bubbles pop
TT_DARK_BASE = (12, 14, 18)         # near-black, a shade under the app's #0F1115
DOODLE_DELTA = 0.07                 # icons 7 % darker (light) / lighter (dark) than the ground

TITI_LIGHT_BASE = (252, 238, 233)   # pale blush
TITI_DARK_BASE = (22, 18, 24)       # plum-ink
TITI_OPACITY = {'light': 0.09, 'dark': 0.10}

# Mock-bubble colours per (wallpaper, mode), mirrored in ChatWallpaperStyle (Dart).
#   mine / theirs: bubble fills; border: theirs' outline (None = none)
#   chip / chip_text: the "Today" divider and the time under stickers and cards
#   label: sender names sitting straight on the wallpaper (meet chats)
LIGHT = dict(mine=(225, 228, 234), theirs=(255, 255, 255), border=(219, 219, 219), text=(0, 0, 0), meta=(115, 115, 115), chip=(255, 255, 255, 219), chip_text=(98, 98, 98), label=(98, 98, 98))
DARK = dict(mine=(35, 39, 47), theirs=(22, 25, 32), border=(46, 51, 60), text=(242, 243, 245), meta=(154, 160, 168), chip=(22, 25, 32, 224), chip_text=(170, 176, 184), label=(154, 160, 168))
STYLE = {
    ('ttspot', 'light'): LIGHT,
    ('ttspot', 'dark'): DARK,
    # Night: light bubbles read on the dusk as they are; the dark ones get a stronger fill and edge.
    ('night', 'light'): dict(LIGHT, border=None, chip=(0, 0, 0, 92), chip_text=(255, 255, 255), label=(255, 255, 255, 230)),
    ('night', 'dark'): dict(DARK, mine=(43, 47, 57), theirs=(30, 33, 42), border=(56, 61, 72), chip=(0, 0, 0, 110), chip_text=(225, 228, 233), label=(201, 205, 212)),
    ('titi', 'light'): LIGHT,
    ('titi', 'dark'): DARK,
}
# App chrome (AppColors light / dark) for the mock's app bar and composer.
CHROME = {
    'light': dict(bg=(255, 255, 255), text=(0, 0, 0), sub=(115, 115, 115), field=(250, 250, 250), gray=(239, 239, 239), border=(219, 219, 219)),
    'dark': dict(bg=(15, 17, 21), text=(242, 243, 245), sub=(154, 160, 168), field=(28, 31, 38), gray=(35, 39, 47), border=(46, 51, 60)),
}


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def doodle_ink(base, mode):
    if mode == 'light':
        return tuple(round(c * (1 - DOODLE_DELTA)) for c in base)
    return tuple(round(c + 255 * DOODLE_DELTA) for c in base)


# --------------------------------------------------------------- scattering ---
def torus_d2(a, b, size):
    dx = abs(a[0] - b[0]); dx = min(dx, size - dx)
    dy = abs(a[1] - b[1]); dy = min(dy, size - dy)
    return dx * dx + dy * dy


def scatter(rng, size, radius, tries=20000, taken=()):
    """Dart-throwing on a torus: points at least 2*radius apart (and clear of [taken])."""
    pts = []
    for _ in range(tries):
        p = (rng.uniform(0, size), rng.uniform(0, size))
        if all(torus_d2(p, q, size) >= (radius + r) ** 2 for q, r in taken) and all(torus_d2(p, q, size) >= (2 * radius) ** 2 for q in pts):
            pts.append(p)
    return pts


def paste_wrapped(canvas, sprite, cx, cy, size, mask=None):
    """Paste [sprite] centred on (cx, cy) and again shifted by the tile size, so the tile is seamless."""
    w, h = sprite.size
    for dx in (-size, 0, size):
        for dy in (-size, 0, size):
            x, y = round(cx + dx - w / 2), round(cy + dy - h / 2)
            if x + w < 0 or y + h < 0 or x > size or y > size:
                continue
            if mask is None:
                canvas.alpha_composite(sprite, (x, y)) if canvas.mode == 'RGBA' else canvas.paste(255, (x, y), sprite)
            else:
                canvas.paste(255, (x, y), mask)


_fonts = {}


def glyph_mask(cp, px, angle, erode):
    """A Phosphor glyph as an L mask at px size (already supersampled), thinned and rotated."""
    f = _fonts.get(px) or _fonts.setdefault(px, ImageFont.truetype(PHOSPHOR, px))
    im = Image.new('L', (px * 2, px * 2), 0)
    ImageDraw.Draw(im).text((px // 2, px // 2), chr(cp), font=f, fill=255)
    im = im.crop(im.getbbox())
    if erode:
        im = im.filter(ImageFilter.MinFilter(erode))
    pad = px // 4
    framed = Image.new('L', (im.width + pad * 2, im.height + pad * 2), 0)
    framed.paste(im, (pad, pad))
    return framed.rotate(angle, resample=Image.BICUBIC, expand=True)


# ------------------------------------------------------------------ TT Spot ---
def ttspot_mask():
    rng = random.Random(7)
    big = TILE * SS
    canvas = Image.new('L', (big, big), 0)
    bag = [g for g, w in DOODLES for _ in range(w)]
    pts = scatter(rng, TILE, 40)
    rng.shuffle(pts)
    taken = []
    last = None
    for i, (x, y) in enumerate(pts):
        g = rng.choice(bag)
        while g == last:
            g = rng.choice(bag)
        last = g
        px = rng.randint(48, 60)
        m = glyph_mask(G[g], px * SS, rng.uniform(-28, 28), erode=3)
        paste_wrapped(canvas, m, x * SS, y * SS, big)
        taken.append(((x, y), 30))
    # Fillers in the gaps: tiny sparkles, rings and dots, like the WhatsApp doodle.
    d = ImageDraw.Draw(canvas)
    for (x, y) in scatter(random.Random(11), TILE, 13, taken=taken):
        kind = rng.random()
        if kind < 0.3:
            m = glyph_mask(G['sparkle'] if rng.random() < 0.6 else G['star'], 18 * SS, rng.uniform(-20, 20), erode=3)
            paste_wrapped(canvas, m, x * SS, y * SS, big)
        else:
            r = (4.5 if kind < 0.65 else 2.6) * SS
            for dx in (-big, 0, big):
                for dy in (-big, 0, big):
                    cx, cy = x * SS + dx, y * SS + dy
                    if kind < 0.65:
                        d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=255, width=round(2.2 * SS))
                    else:
                        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    return canvas.reduce(SS), len(pts)


def ttspot(mode, mask):
    base = TT_LIGHT_BASE if mode == 'light' else TT_DARK_BASE
    ink = doodle_ink(base, mode)
    return Image.composite(Image.new('RGB', mask.size, ink), Image.new('RGB', mask.size, base), mask)


# -------------------------------------------------------------------- night ---
def vgradient(w, h, stops):
    """Vertical gradient through [(t, rgb), ...]."""
    line = Image.new('RGB', (1, 256))
    for i in range(256):
        t = i / 255
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t0 <= t <= t1:
                k = (t - t0) / (t1 - t0) if t1 > t0 else 0
                k = k * k * (3 - 2 * k)
                line.putpixel((0, i), lerp(c0, c1, k))
                break
    return line.resize((w, h), Image.BICUBIC)


def glow(size, box, color, alpha, blur):
    layer = Image.new('RGBA', size, color + (0,))
    a = Image.new('L', size, 0)
    ImageDraw.Draw(a).ellipse(box, fill=alpha)
    layer.putalpha(a.filter(ImageFilter.GaussianBlur(blur)))
    return layer


def night(mode):
    w, h = NIGHT_W, NIGHT_H
    if mode == 'dark':
        stops = [(0, (8, 12, 26)), (0.45, (13, 15, 28)), (0.78, (34, 10, 22)), (1, (62, 8, 18))]
        bokeh = [(255, 196, 120), (255, 92, 92), (190, 210, 255), (255, 255, 255)]
        bokeh_a, lane_a, haze = (16, 46), 26, ((150, 10, 28), 70)
    else:
        stops = [(0, (52, 64, 98)), (0.42, (88, 82, 120)), (0.78, (150, 86, 104)), (1, (176, 78, 86))]
        bokeh = [(255, 214, 160), (255, 150, 140), (220, 230, 255), (255, 255, 255)]
        bokeh_a, lane_a, haze = (20, 52), 34, ((236, 120, 110), 60)
    im = vgradient(w, h, stops).convert('RGBA')
    # Tail-light haze at the bottom and a faint glow on the horizon.
    im.alpha_composite(glow((w, h), (-w * 0.3, h * 0.78, w * 1.3, h * 1.25), haze[0], haze[1], 120))
    horizon = h * 0.60
    im.alpha_composite(glow((w, h), (-w * 0.2, horizon - 90, w * 1.2, horizon + 90), (255, 170, 120) if mode == 'light' else (120, 60, 90), 40, 60))

    # City-light bokeh along the horizon band, softly blurred.
    rng = random.Random(23)
    for layer_blur, count, rmin, rmax in ((14, 22, 26, 52), (6, 34, 10, 24), (2.5, 46, 3, 8)):
        lay = Image.new('RGBA', (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(lay)
        for _ in range(count):
            x = rng.uniform(-20, w + 20)
            y = rng.gauss(horizon - 70, 120)
            y = min(max(y, h * 0.10), horizon + 40)
            r = rng.uniform(rmin, rmax)
            c = rng.choice(bokeh)
            d.ellipse((x - r, y - r, x + r, y + r), fill=c + (round(rng.uniform(*bokeh_a)),))
        im.alpha_composite(lay.filter(ImageFilter.GaussianBlur(layer_blur)))

    # Lane lines: a road running into the horizon, drawn supersampled.
    big = Image.new('L', (w * SS, h * SS), 0)
    d = ImageDraw.Draw(big)
    vx, vy = w * 0.5 * SS, horizon * SS
    bottom = h * SS * 1.02
    for edge in (-1.25, 1.25):
        d.line((vx, vy, vx + edge * w * SS, bottom), fill=255, width=round(3 * SS))
    # Dashed centre lines, getting longer and wider towards the viewer.
    for lane in (-0.42, 0.42):
        t = 0.04
        while t < 1:
            t2 = t + 0.035 + t * 0.12
            x1, y1 = vx + lane * w * SS * t, vy + (bottom - vy) * t
            x2, y2 = vx + lane * w * SS * min(t2, 1), vy + (bottom - vy) * min(t2, 1)
            d.line((x1, y1, x2, y2), fill=255, width=max(1, round((1 + 4 * t) * SS)))
            t = t2 + 0.03 + t * 0.10
    lanes = big.reduce(SS)
    # Fade the lines out towards the horizon.
    fade = vgradient(w, h, [(0, (0, 0, 0)), (horizon / h, (0, 0, 0)), (horizon / h + 0.12, (90, 90, 90)), (1, (255, 255, 255))]).convert('L')
    lanes = ImageChops.multiply(lanes, fade).point(lambda v: v * lane_a // 255)
    white = Image.new('RGBA', (w, h), (255, 255, 255, 0))
    white.putalpha(lanes)
    im.alpha_composite(white)

    # A whisper of grain so the gradient doesn't band once compressed.
    noise = Image.effect_noise((w, h), 9).point(lambda v: 128 + (v - 128) // 3)
    grain = Image.merge('RGB', (noise, noise, noise))
    out = ImageChops.add(im.convert('RGB'), grain, 1, -128)
    return out


# --------------------------------------------------------------------- TiTi ---
HEAD_POSES = ['wave', 'celebrate', 'thumbsup', 'sad', 'bell', 'phone', 'stop', 'voucher', 'mappin']


def titi_head(pose, px):
    """TiTi's cone head (tip to cheeks) cut out of a pose, about px tall."""
    im = Image.open(os.path.join(ROOT, 'assets', 'titi', f'{pose}.png')).convert('RGBA')
    # Cone-shaped cut with a rounded chin under the cheeks, so arms, hands and the sash stay out.
    cone = Image.new('L', im.size, 0)
    ImageDraw.Draw(cone).polygon([(322, 0), (398, 0), (542, 372), (178, 372)], fill=255)
    chin = Image.new('L', im.size, 0)
    d = ImageDraw.Draw(chin)
    d.rectangle((0, 0, im.width, 300), fill=255)
    d.ellipse((182, 222, 538, 368), fill=255)
    m = ImageChops.multiply(cone, chin).filter(ImageFilter.GaussianBlur(2.5))
    im.putalpha(ImageChops.multiply(im.split()[3], m))
    im = im.crop((170, 0, 550, 372))
    return im.resize((round(px * im.width / im.height), px), Image.LANCZOS)


def titi(mode):
    rng = random.Random(31)
    base = TITI_LIGHT_BASE if mode == 'light' else TITI_DARK_BASE
    layer = Image.new('RGBA', (TILE, TILE), (0, 0, 0, 0))
    heads = scatter(rng, TILE, 62)
    rng.shuffle(heads)
    taken = []
    for i, (x, y) in enumerate(heads):
        h = titi_head(HEAD_POSES[i % len(HEAD_POSES)], rng.randint(78, 92)).rotate(rng.uniform(-18, 18), resample=Image.BICUBIC, expand=True)
        paste_wrapped(layer, h, x, y, TILE)
        taken.append(((x, y), 52))
    # Line cones and little hearts in between, in TiTi red.
    big = TILE * SS
    mask = Image.new('L', (big, big), 0)
    for (x, y) in scatter(random.Random(37), TILE, 26, taken=taken):
        g = 'cone' if rng.random() < 0.7 else 'heart'
        m = glyph_mask(G[g], (rng.randint(30, 38) if g == 'cone' else rng.randint(20, 24)) * SS, rng.uniform(-25, 25), erode=3)
        paste_wrapped(mask, m, x * SS, y * SS, big)
    mask = mask.reduce(SS)
    red = Image.new('RGBA', (TILE, TILE), (224, 0, 8, 0))
    red.putalpha(mask)
    layer.alpha_composite(red)
    op = TITI_OPACITY[mode]
    layer.putalpha(layer.split()[3].point(lambda v: round(v * op)))
    out = Image.new('RGBA', (TILE, TILE), base + (255,))
    out.alpha_composite(layer)
    return out.convert('RGB'), len(heads)


# ------------------------------------------------------------- preview mock ---
FONT_DIR = 'C:/Windows/Fonts'


def font(size, bold=False):
    for name in (('segoeuib.ttf', 'arialbd.ttf') if bold else ('segoeui.ttf', 'arial.ttf')):
        p = os.path.join(FONT_DIR, name)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def icon(d, xy, name, size, fill):
    d.text(xy, chr(G.get(name) or name), font=ImageFont.truetype(PHOSPHOR, size), fill=fill)


def wallpaper_fill(wid, mode, w, h, img):
    """The wallpaper as the app lays it out: tiles at scale 2 (mock is drawn at 2x), night covers from the bottom."""
    if wid == 'night':
        k = w / img.width
        s = img.resize((w, round(img.height * k)), Image.LANCZOS)
        return s.crop((0, s.height - h, w, s.height))
    out = Image.new('RGB', (w, h))
    for x in range(0, w, img.width):
        for y in range(0, h, img.height):
            out.paste(img, (x, y))
    return out


def rounded(d, box, r, fill, outline=None, corners=None):
    d.rounded_rectangle(box, r, fill=fill, outline=outline, width=2 if outline else 0, corners=corners)


def bubble(im, d, text, time, mine, st, y, W):
    f, ft = font(30), font(22)
    pad_x, pad_y = 28, 16
    tw = d.textlength(text, font=f)
    tmw = d.textlength(time, font=ft)
    bw = tw + 24 + tmw + pad_x * 2
    bh = 44 + pad_y * 2
    x = W - 24 - bw if mine else 24
    fill = st['mine'] if mine else st['theirs']
    outline = None if mine else st['border']
    # Pillow corners order: top-left, top-right, bottom-right, bottom-left. The tail corner stays square.
    corners = (True, True, False, True) if mine else (True, True, True, False)
    rounded(d, (x, y, x + bw, y + bh), 36, fill, outline, corners)
    d.text((x + pad_x, y + pad_y + 2), text, font=f, fill=st['text'])
    d.text((x + bw - pad_x - tmw, y + bh - pad_y - 26), time, font=ft, fill=st['meta'])
    return y + bh + 12


def chip(im, text, cx, y, st):
    f = font(23, bold=True)
    layer = Image.new('RGBA', im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    w = d.textlength(text, font=f) + 40
    d.rounded_rectangle((cx - w / 2, y, cx + w / 2, y + 46), 23, fill=st['chip'])
    d.text((cx - w / 2 + 20, y + 7), text, font=f, fill=st['chip_text'])
    im.alpha_composite(layer)
    return y + 46


def mock(wid, mode, img, W=760, H=1500):
    """A phone-sized chat (drawn at 2x) on the wallpaper, with the app's bars and bubbles."""
    c, st = CHROME[mode], STYLE[(wid, mode)]
    im = Image.new('RGBA', (W, H), c['bg'] + (255,))
    bar, comp = 120, 120
    im.paste(wallpaper_fill(wid, mode, W, H - bar - comp, img), (0, bar))
    d = ImageDraw.Draw(im)
    # App bar
    icon(d, (24, 38), 0xe058, 44, c['text'])
    d.ellipse((90, 30, 154, 94), fill=(224, 0, 8))
    d.text((106, 40), 'T', font=font(34, bold=True), fill=(255, 255, 255))
    d.text((172, 26), 'TiTi Onboard', font=font(31, bold=True), fill=c['text'])
    d.text((172, 66), '@titi_onboard1', font=font(23), fill=c['sub'])
    icon(d, (W - 70, 38), 0xe208, 44, c['text'])
    d.line((0, bar - 1, W, bar - 1), fill=c['border'], width=1)
    # Messages
    y = bar + 40
    y = chip(im, 'Today', W / 2, y, st) + 30
    d = ImageDraw.Draw(im)
    y = bubble(im, d, 'Jom TT tonight?', '9:41 pm', False, st, y, W)
    y = bubble(im, d, 'Usual spot, TTDI', '9:41 pm', False, st, y, W) + 8
    y = bubble(im, d, 'Otw, 10 min', '9:42 pm', True, st, y, W) + 8
    sticker = Image.open(os.path.join(ROOT, 'assets', 'stickers', 'titi', 'titi_otw.webp')).convert('RGBA').resize((240, 240), Image.LANCZOS)
    im.alpha_composite(sticker, (24, y))
    y += 246
    tl = font(22)
    tw = d.textlength('9:43 pm', font=tl)
    layer = Image.new('RGBA', im.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle((24 + 240 - tw - 28, y, 24 + 240, y + 36), 18, fill=st['chip'])
    im.alpha_composite(layer)
    d = ImageDraw.Draw(im)
    d.text((24 + 240 - tw - 14, y + 4), '9:43 pm', font=tl, fill=st['chip_text'])
    y += 56
    y = bubble(im, d, 'Steady bos, see you', '9:44 pm', True, st, y, W)
    # Composer
    top = H - comp
    d.rectangle((0, top, W, H), fill=c['bg'])
    d.line((0, top, W, top), fill=c['border'], width=1)
    d.ellipse((20, top + 22, 104, top + 106), fill=c['gray'])
    icon(d, (40, top + 42), 0xe3d4, 44, c['text'])
    rounded(d, (120, top + 22, W - 120, top + 106), 42, c['field'], c['border'])
    d.text((150, top + 44), 'Message...', font=font(30), fill=c['sub'])
    d.ellipse((W - 104, top + 22, W - 20, top + 106), fill=(224, 0, 8))
    icon(d, (W - 84, top + 42), 0xe326, 44, (255, 255, 255))
    return im.convert('RGB')


def sheet(walls):
    names = [('titi', 'TiTi (default)'), ('ttspot', 'TT Spot'), ('night', 'Night drive')]
    pw, ph = 456, 900
    gap, top, label = 36, 160, 64
    W = gap + len(names) * (pw + gap)
    H = top + 2 * (ph + label + gap)
    out = Image.new('RGB', (W, H), (236, 233, 228))
    d = ImageDraw.Draw(out)
    d.text((gap, 34), 'TT Spot chat backgrounds', font=font(44, bold=True), fill=(16, 16, 16))
    d.text((gap, 96), 'Settings > Appearance > Chat background, or Chat info in any chat. Top row light mode, bottom row dark mode.', font=font(24), fill=(90, 90, 90))
    for r, mode in enumerate(('light', 'dark')):
        for i, (wid, title) in enumerate(names):
            m = mock(wid, mode, walls[(wid, mode)]).resize((pw, ph), Image.LANCZOS)
            x, y = gap + i * (pw + gap), top + r * (ph + label + gap)
            frame = Image.new('L', (pw, ph), 0)
            ImageDraw.Draw(frame).rounded_rectangle((0, 0, pw - 1, ph - 1), 36, fill=255)
            out.paste(m, (x, y), frame)
            d.rounded_rectangle((x - 1, y - 1, x + pw, y + ph), 36, outline=(190, 186, 180), width=2)
            d.text((x + 4, y + ph + 14), f'{title}  ·  {mode}', font=font(28, bold=True), fill=(16, 16, 16))
    return out


# ---------------------------------------------------------------------- main ---
def save_webp(img, path, lossless=False, quality=86):
    img.save(path, 'WEBP', lossless=lossless, quality=quality, method=6)
    kb = os.path.getsize(path) / 1024
    print(f'  {os.path.relpath(path, ROOT)}  {img.width}x{img.height}  {kb:.0f} KB')
    assert kb < 150, f'{path} is {kb:.0f} KB, keep it under 150'


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(DESIGN, exist_ok=True)
    walls = {}
    mask, n = ttspot_mask()
    print(f'ttspot: {n} doodles')
    for mode in ('light', 'dark'):
        walls[('ttspot', mode)] = ttspot(mode, mask)
        walls[('night', mode)] = night(mode)
        walls[('titi', mode)], heads = titi(mode)
    print(f'titi: {heads} heads')
    for (wid, mode), img in sorted(walls.items()):
        save_webp(img, os.path.join(OUT, f'{wid}_{mode}.webp'), quality=90 if wid != 'night' else 84)
    sheet(walls).save(os.path.join(DESIGN, 'sheet.jpg'), quality=88)
    print('  design/wallpapers/sheet.jpg')


if __name__ == '__main__':
    main()

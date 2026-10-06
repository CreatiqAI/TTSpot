"""Badge tiers (0.3.55): every achievement badge comes in 4 tiers, 1 Bronze,
2 Silver, 3 Platinum, 4 Gold. Gold is the existing red-enamel + polished-gold
pin from batch 3; the other three keep the SAME emblem, shape and angle and only
change the metal, the enamel palette and one ornament per tier:

  1 Bronze    warm bronze metal, chocolate brown + cream enamel, plain rim
  2 Silver    polished silver metal, navy + charcoal + white enamel, beaded rim
  3 Platinum  bright platinum metal, icy blue + steel blue + white enamel,
              a small diamond set in the rim at the top and a few glints
  4 Gold      the existing art (red + black + white enamel, gold metal)

How: the gold pin is first recoloured into the tier palette here with Pillow
(a luminance-preserving gradient map per material: metal / red / black / white
enamel), which pins the colours so one tier looks the same on every badge. That
recolour is the reference for Kie GPT Image 2 image-to-image, which re-renders
it as a real metal pin and adds the tier ornament.

  python tool/art_badge_tiers.py --refs                 # only build the recoloured references (free)
  python tool/art_badge_tiers.py                        # render every missing raw image (15 renders, ~6 Kie credits each)
  python tool/art_badge_tiers.py explorer_2 popular_3   # just some keys
  python tool/art_badge_tiers.py --force explorer_2     # regenerate (old raw kept as <key>.old.png)
  python tool/art_badge_tiers.py --install              # clean, trim, square to 288 px, save into assets/badges
  python tool/art_badge_tiers.py --sheet out.png        # contact sheet of the installed 20 (dark + light)

Gold sources: tool/titi_gen/batch3/badge_<src>.png (1254 px raw) when present,
else assets/badges/<src>.png. Raw output: tool/titi_gen/badge_tiers/ (git-ignored).
Installed: assets/badges/<id>_<tier>.png. Needs ~/.supabase/ttspot-kie-key.txt
(never commit it). Kie rate-limits bursts (429), so tasks are created ~4 s apart.
"""
import json, os, shutil, sys, time, uuid, urllib.request

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(ROOT)
OUT = os.path.join(ROOT, 'titi_gen', 'badge_tiers')
REFS = os.path.join(OUT, 'refs')
os.makedirs(REFS, exist_ok=True)
SIZE = 288  # same canvas as the batch 3 badges in assets/badges
FIT = 282   # the pin's longer side inside the square (3 px margin, as before)

# Badge id (what the app loads) -> the gold source art.
# organizer: the megaphone reads far better at 40 px than the convoy shield
# (three tiny cars). joiner: two cars meeting says "car meet" better than the
# calendar of check marks.
BADGES = {
    'posts': 'first_post',
    'organizer': 'organiser',
    'joiner': 'first_meet',
    'explorer': 'explorer',
    'popular': 'popular',
}
TIERS = (1, 2, 3, 4)
NAMES = {1: 'Bronze', 2: 'Silver', 3: 'Platinum', 4: 'Gold'}


def key():
    return open(os.path.expanduser('~/.supabase/ttspot-kie-key.txt')).read().strip()


def post_json(url, body):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={'Authorization': f'Bearer {key()}', 'Content-Type': 'application/json'})
    return json.load(urllib.request.urlopen(req, timeout=60))


def get_json(url):
    return json.load(urllib.request.urlopen(urllib.request.Request(url, headers={'Authorization': f'Bearer {key()}'}), timeout=60))


def upload(local):
    mime = 'image/png' if local.endswith('.png') else 'image/jpeg'
    b = uuid.uuid4().hex
    data = open(local, 'rb').read()
    body = (f'--{b}\r\nContent-Disposition: form-data; name="uploadPath"\r\n\r\nttspot/art\r\n--{b}\r\nContent-Disposition: form-data; name="file"; filename="{os.path.basename(local)}"\r\nContent-Type: {mime}\r\n\r\n').encode() + data + f'\r\n--{b}--\r\n'.encode()
    req = urllib.request.Request('https://kieai.redpandaai.co/api/file-stream-upload', data=body, headers={'Authorization': f'Bearer {key()}', 'Content-Type': f'multipart/form-data; boundary={b}'})
    return json.load(urllib.request.urlopen(req, timeout=120))['data']['downloadUrl']


def credits():
    try:
        return get_json('https://api.kie.ai/api/v1/chat/credit').get('data')
    except Exception:
        return None


def gold_source(src):
    raw = os.path.join(ROOT, 'titi_gen', 'batch3', f'badge_{src}.png')
    return raw if os.path.exists(raw) else os.path.join(REPO, 'assets', 'badges', src + '.png')


# ---------------------------------------------------------------- recolour --
# Gradient maps per material, as (position, colour) stops over the pixel's
# brightness. Red enamel in the gold art sits around V 0.70-0.80 with shadows
# near 0.4 and highlights near 1, so the stops are placed around those.
PALETTES = {
    1: dict(  # Bronze
        metal=[(0, '#20120a'), (0.3, '#5e3519'), (0.55, '#a5622c'), (0.78, '#d5904f'), (0.92, '#f2c48c'), (1, '#fff0dc')],
        red=[(0, '#0e0703'), (0.4, '#2c170b'), (0.72, '#4f2c18'), (0.88, '#74472b'), (1, '#c99f80')],
        black=[(0, '#0b0603'), (0.25, '#1d1009'), (0.55, '#4a3322'), (1, '#e9d6bf')],
        white=[(0, '#5e4830'), (0.5, '#c7ad82'), (0.8, '#eadab6'), (1, '#fbf2de')],
    ),
    2: dict(  # Silver
        metal=[(0, '#15181c'), (0.3, '#4f565f'), (0.55, '#959ea8'), (0.78, '#cfd6de'), (0.92, '#eef2f6'), (1, '#ffffff')],
        red=[(0, '#040814'), (0.4, '#0c1834'), (0.72, '#1b3366'), (0.88, '#2f4f8f'), (1, '#a9bfe6')],
        black=[(0, '#08090b'), (0.25, '#1a1d22'), (0.55, '#474e58'), (1, '#e2e6eb')],
        white=[(0, '#4a5560'), (0.5, '#c2cad4'), (0.8, '#edf1f5'), (1, '#ffffff')],
    ),
    3: dict(  # Platinum
        metal=[(0, '#36414c'), (0.3, '#7d8a97'), (0.55, '#c3ccd5'), (0.78, '#e9eef3'), (0.92, '#f8fafc'), (1, '#ffffff')],
        red=[(0, '#123a52'), (0.4, '#2c78a6'), (0.72, '#62b9e4'), (0.88, '#93d4f2'), (1, '#e3f7ff')],
        black=[(0, '#0a1d2a'), (0.25, '#173a52'), (0.55, '#3f7597'), (1, '#e0f1fa')],
        white=[(0, '#7a90a2'), (0.5, '#d6e3ec'), (0.8, '#f3f8fb'), (1, '#ffffff')],
    ),
}


def _rgb(h):
    return [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]


def _ramp(stops, t):
    pos = [p for p, _ in stops]
    cols = np.array([_rgb(c) for _, c in stops])
    return np.stack([np.interp(t, pos, cols[:, c]) for c in range(3)], -1)


def clean_alpha(im):
    """Kie's transparent PNGs carry a semi-transparent coloured fringe: make
    alpha binary (below 150 -> 0, else 255); LANCZOS downscaling later gives a
    clean anti-aliased edge."""
    im = im.convert('RGBA')
    im.putalpha(im.getchannel('A').point(lambda v: 0 if v < 150 else 255))
    return im


def logo_mask(im):
    """popular: the TT logo (white left T, red right T + chequered flag) keeps
    the brand colours on every tier. Inside the logo box, red pixels that are
    NOT connected to the star's big red field or the two lower hearts (gold
    outlines cut the logo off from them) plus the white pixels are the logo."""
    w, h = im.size
    box = (int(w * .30), int(h * .37), int(w * .79), int(h * .69))
    rgb = np.array(im.convert('RGB'), int)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    red = (r > 110) & (r > g * 2.2) & (r > b * 2.2)
    white = (r > 170) & (g > 170) & (b > 160) & (np.abs(r - g) < 40)
    m = Image.fromarray((red * 255).astype(np.uint8), 'L').copy()  # copy: a fromarray image ignores floodfill writes
    for seed in ((.5, .3), (.2, .72), (.8, .73)):  # star field above the logo, lower-left and lower-right hearts
        ImageDraw.floodfill(m, (int(w * seed[0]), int(h * seed[1])), 128)
    field = np.array(m) == 128
    inbox = np.zeros_like(red)
    inbox[box[1]:box[3], box[0]:box[2]] = True
    return inbox & ((red & ~field) | white)


def recolor(src_path, tier, keep_logo=False):
    im = clean_alpha(Image.open(src_path))
    a = np.array(im.getchannel('A'))
    rgb = np.array(im.convert('RGB'), float) / 255
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = np.maximum(mx - mn, 1e-6)
    s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    sat_w = np.clip((s - 0.15) / 0.25, 0, 1)
    gold_w = sat_w * np.clip(1 - np.abs(hue - 42) / 22, 0, 1)
    red_w = sat_w * np.clip(1 - np.minimum(hue, 360 - hue) / 22, 0, 1)
    rest = np.clip(1 - gold_w - red_w, 0, 1)
    dark_w = rest * np.clip((0.35 - mx) / 0.2, 0, 1)
    white_w = rest - dark_w
    p = PALETTES[tier]
    out = (gold_w[..., None] * _ramp(p['metal'], np.clip(lum * 1.15, 0, 1))
           + red_w[..., None] * _ramp(p['red'], mx)
           + dark_w[..., None] * _ramp(p['black'], mx)
           + white_w[..., None] * _ramp(p['white'], lum))
    out = np.clip(out, 0, 1)
    if keep_logo:
        m = logo_mask(im)
        out[m] = rgb[m]
    return Image.fromarray(np.dstack([(out * 255).round().astype(np.uint8), a]), 'RGBA')


def build_refs(only=None):
    paths = {}
    for bid, src in BADGES.items():
        for tier in (1, 2, 3):
            k = f'{bid}_{tier}'
            if only and k not in only:
                continue
            dst = os.path.join(REFS, k + '.png')
            recolor(gold_source(src), tier, keep_logo=(bid == 'popular')).save(dst)
            paths[k] = dst
    print('refs:', len(paths), flush=True)
    return paths


# ----------------------------------------------------------------- prompts --
BASE = ('The reference image is a collectible hard-enamel lapel pin badge. Recreate this exact same pin: the identical outline shape, '
        'the identical emblem and artwork with every detail in the same place, the same layout, proportions, angle and framing, and '
        'the same enamel colour in every area as the reference (do not recolour anything). Fine raised metal lines separate the '
        'enamel areas, glossy enamel, slight 3D depth, soft studio light, front view. Isolated on a transparent background, centred, '
        'nothing else around it, no text, no letters, no numbers, no extra objects, no shadow. ')
FINISH = {
    1: ('Tier: BRONZE. Every metal part (the outer rim and all raised lines) is warm polished bronze, a rich copper-brown metal '
        'with soft warm highlights, clearly not gold and not yellow. Enamel: chocolate brown, deep brown-black and cream, as in the '
        'reference. The outer rim is plain and smooth, with no ornaments.'),
    2: ('Tier: SILVER. Every metal part (the outer rim and all raised lines) is polished bright sterling silver with cool chrome '
        'reflections, clearly not gold. Enamel: deep navy blue, dark charcoal and white, as in the reference. The outer metal rim '
        'carries a thin row of tiny raised silver beads running all the way around the outline (a beaded edge), within the '
        'existing rim width so the pin keeps the same size and outline.'),
    3: ('Tier: PLATINUM. Every metal part (the outer rim and all raised lines) is bright polished platinum, a cool, very light '
        'white-silver metal with crisp highlights, clearly not gold. Enamel: icy light blue, deep steel blue and white, as in the '
        'reference. One small brilliant-cut clear diamond is set flush into the outer rim at the very top centre of the pin, plus '
        'two or three tiny white sparkle glints on the rim; nothing sticks out beyond the pin outline.'),
}
EXTRA = {
    'popular': (' The TT logo in the middle stays exactly as in the reference and keeps its brand colours on this tier: the left '
                'T is white, the right T is red with the small red chequered flag above its top right. Do not change the logo.'),
}


def prompt(bid, tier):
    return BASE + FINISH[tier] + EXTRA.get(bid, '')


# --------------------------------------------------------------------- Kie --
def run(jobs, force=False):
    tasks = {}
    for k, (text, refs) in jobs.items():
        raw = os.path.join(OUT, k + '.png')
        if os.path.exists(raw):
            if not force:
                print('skip (exists)', k, flush=True)
                continue
            shutil.move(raw, os.path.join(OUT, k + '.old.png'))
        inp = {'prompt': text, 'input_urls': refs, 'aspect_ratio': '1:1', 'resolution': '1K', 'background': 'transparent'}
        for attempt in range(4):
            try:
                r = post_json('https://api.kie.ai/api/v1/jobs/createTask', {'model': 'gpt-image-2-image-to-image', 'input': inp})
            except Exception as e:
                r = {'code': 'ERR', 'msg': str(e)}
            if r.get('code') == 200:
                break
            time.sleep(15)
        tasks[k] = (r.get('data') or {}).get('taskId')
        print('task', k, r.get('code'), r.get('msg'), flush=True)
        time.sleep(4)
    done = set()
    for _ in range(150):
        pending = [k for k, t in tasks.items() if t and k not in done]
        if not pending:
            break
        time.sleep(12)
        for k in pending:
            try:
                d = (get_json(f'https://api.kie.ai/api/v1/jobs/recordInfo?taskId={tasks[k]}').get('data') or {})
            except Exception as e:
                print('poll err', k, e, flush=True)
                continue
            if d.get('state') == 'success':
                url = json.loads(d['resultJson'])['resultUrls'][0]
                for attempt in range(3):
                    try:
                        open(os.path.join(OUT, k + '.png'), 'wb').write(urllib.request.urlopen(url, timeout=600).read())
                        break
                    except Exception as e:
                        print('retry download', k, e, flush=True)
                done.add(k)
                print('done', k, flush=True)
            elif d.get('state') == 'fail':
                done.add(k)
                print('FAIL', k, d.get('failMsg'), flush=True)
    print('missing:', [k for k in jobs if not os.path.exists(os.path.join(OUT, k + '.png'))], flush=True)


# ----------------------------------------------------------------- install --
# Hand fixes on the raw render, as (x0, y0, x1, y1) boxes made transparent
# before trimming. joiner_3: a sparkle streak shot up out of the rim above the
# diamond, which would also have shrunk the pin when trimmed.
ERASE = {
    'joiner_3': [(610, 0, 672, 107)],
}


def square(im, erase=()):
    """Clean the fringe, trim to the pin, fit the longer side to FIT px and
    centre it on a transparent SIZE px square."""
    im = clean_alpha(im)
    for box in erase:
        im.paste((0, 0, 0, 0), box)
    im = im.crop(im.getchannel('A').getbbox())
    k = FIT / max(im.size)
    im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
    out = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    out.alpha_composite(im, ((SIZE - im.width) // 2, (SIZE - im.height) // 2))
    return out


def install():
    for bid, src in BADGES.items():
        for tier in TIERS:
            raw = gold_source(src) if tier == 4 else os.path.join(OUT, f'{bid}_{tier}.png')
            if not os.path.exists(raw):
                print('MISSING', raw, flush=True)
                continue
            dst = os.path.join(REPO, 'assets', 'badges', f'{bid}_{tier}.png')
            square(Image.open(raw), ERASE.get(f'{bid}_{tier}', ())).save(dst, optimize=True)
            print('installed', os.path.relpath(dst, REPO), os.path.getsize(dst), 'bytes', flush=True)


def sheet(dst, cell=150, pad=12):
    """Rows = badges, columns = tiers; the dark half on top, the light half below."""
    from PIL import ImageFont
    try:
        font = ImageFont.truetype('arial.ttf', 15)
    except Exception:
        font = ImageFont.load_default()
    head, left = 30, 90
    half = head + cell * len(BADGES)
    W, H = left + cell * 4, half * 2
    out = Image.new('RGBA', (W, H), (0, 0, 0, 255))
    dr = ImageDraw.Draw(out)
    for y0, bg, fg in ((0, (24, 24, 27, 255), (230, 230, 230)), (half, (250, 250, 250, 255), (40, 40, 40))):
        dr.rectangle((0, y0, W, y0 + half), fill=bg)
        for j, tier in enumerate(TIERS):
            dr.text((left + j * cell + cell // 2, y0 + head // 2), f'{tier} {NAMES[tier]}', fill=fg, font=font, anchor='mm')
        for i, bid in enumerate(BADGES):
            dr.text((8, y0 + head + i * cell + cell // 2), bid, fill=fg, font=font, anchor='lm')
            for j, tier in enumerate(TIERS):
                p = os.path.join(REPO, 'assets', 'badges', f'{bid}_{tier}.png')
                if not os.path.exists(p):
                    continue
                im = Image.open(p).convert('RGBA').resize((cell - pad, cell - pad), Image.LANCZOS)
                out.alpha_composite(im, (left + j * cell + pad // 2, y0 + head + i * cell + pad // 2))
    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    out.convert('RGB').save(dst, optimize=True)
    print('sheet', dst, flush=True)


if __name__ == '__main__':
    args = sys.argv[1:]
    if '--install' in args:
        install()
        sys.exit()
    if '--sheet' in args:
        sheet(args[args.index('--sheet') + 1])
        sys.exit()
    only = {a for a in args if not a.startswith('--')}
    refs = build_refs(only or None)
    if '--refs' in args:
        sys.exit()
    force = '--force' in args
    before = credits()
    jobs = {}
    for k, path in refs.items():
        bid, tier = k.rsplit('_', 1)
        if os.path.exists(os.path.join(OUT, k + '.png')) and not force:
            continue
        jobs[k] = (prompt(bid, int(tier)), [upload(path)])
    run(jobs, force)
    after = credits()
    print('Kie credits:', before, '->', after, flush=True)

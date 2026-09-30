"""Blind-box cards v3: the v1 TiTi figures (sitting, v1 poses, props and faces) in the v2 frame
and tier system, on pale clean backgrounds, with the real TT Spot logo composited by Pillow.

The owner's verdict on v2 (design/cards_v2/): keep the frames and tiers, drop the standing
poses and the display bases. So per card:

  figure, props, title   exactly as on the v1 card (design/cards_v1/cN.jpg), no display base
  frame, tag, SERIES box the v2 tier system (design/cards_v2/cN.jpg)
                           COMMON 01-04 clean white frame, small grey COMMON tag
                           RARE   05-06 silver holographic foil frame, silver RARE tag
                           SECRET 07    gold holographic foil frame, gold SECRET tag
  background             a very light tint of the card's colour, a smooth soft gradient and one
                           or two faint large v1 motifs; no small text, notes or taglines
  logo                   assets/brand/logo.png pasted by Pillow at the v1 place and scale;
                           07 gets the co-branding row: logo, '×', the TypeOne badge cropped
                           from design/cards_v1/c7.jpg

Kie GPT Image 2 image-to-image, two references per card:
  1. the v1 card (the image being edited: TiTi, props, title)
  2. a FRAME-ONLY reference: the matching v2 card with its artwork panel blanked to the v3 pale
     tint (only the frame, the tier tag and the SERIES box are left), so the model cannot copy
     the v2 standing figure or display base.

  python tool/art_cards_v3.py --refs          # build the frame-only references (tool/titi_gen/cards_v3/ref_cN.png)
  python tool/art_cards_v3.py                 # generate every missing raw image
  python tool/art_cards_v3.py c1 c3           # just some keys
  python tool/art_cards_v3.py --force c3      # regenerate (old raw kept as <key>.v<n>.png)
  python tool/art_cards_v3.py --print         # show the prompts
  python tool/art_cards_v3.py --install       # 768x1152 JPGs + logo/co-branding + fixes into design/cards_v3/
  python tool/art_cards_v3.py --sheets        # design/cards_v3/lineup.jpg and compare.jpg (v1 / v2 / v3)
  python tool/art_cards_v3.py --ship          # design/cards_v3/cN.jpg -> assets/cards/cN.jpg (ONLY after the owner approves)

Raw output: tool/titi_gen/cards_v3/<key>.png (git-ignored). Needs ~/.supabase/ttspot-kie-key.txt
(never commit it). Kie rate-limits bursts (429), so tasks are created ~4 s apart.

What was made (2026-10-01): 7 images in one pass, no retries, Kie credits 56 -> 8 (48 spent).
  Every figure came out a near copy of its v1 figure (same sitting pose, props in the same hands,
  same face, sash and proportions), checked side by side with v1 at the same size. 07's v1 figure
  is not sitting but a low kneeling lunge with the TypeOne bar (on a podium); v3 keeps exactly that
  v1 pose, with the podium removed.
  Every title, short line, tag and SERIES number came out clean: no text composites.
  Pillow, on every card: the brand logo PNG at the v1 place and scale (LOGO_*); on 07 the row
  logo, '×', TypeOne badge cut from the v1 card (typeone_badge).
  Pillow fixes (FIXES): c6 a dark-green sliver between the RARE tag and the frame, repainted mint;
  c7 a dark foil plate behind the SECRET pill, repainted with the pale background.
  NOT shipped: assets/cards/ keeps the v1 art (restored on main) until the owner signs off on v3.
"""
import json, os, shutil, sys, time, uuid, urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(ROOT)
OUT = os.path.join(ROOT, 'titi_gen', 'cards_v3')
DST = os.path.join(REPO, 'design', 'cards_v3')
V1 = os.path.join(REPO, 'design', 'cards_v1')
V2 = os.path.join(REPO, 'design', 'cards_v2')
LOGO = os.path.join(REPO, 'assets', 'brand', 'logo.png')
os.makedirs(OUT, exist_ok=True)
CARD = (768, 1152)  # assets/cards/c*.jpg


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


# ---------------------------------------------------------------- the system

TIERS = {
    'common': {
        'frame': ('a clean white card frame (plain white border, slightly rounded outer corners, no foil, no rainbow, no coloured '
                  'corner shapes) with a subtle thin light-grey inner border line around the artwork panel'),
        'series': 'a white rounded box with a thin light-grey edge, set into a white notch of the frame',
        'tag': "a small light-grey pill tag reading 'COMMON' in dark-grey capitals",
        'word': 'COMMON',
    },
    'rare': {
        'frame': ('a polished silver holographic foil card frame (a cool silver sheen with a soft rainbow iridescence, like a '
                  'premium rare trading-card foil border)'),
        'series': 'a white rounded box with a polished silver holographic foil edge, set into a foil notch of the frame',
        'tag': "a small polished silver holographic foil tag reading 'RARE' in black capitals",
        'word': 'RARE',
    },
    'secret': {
        'frame': ('a polished gold holographic foil card frame (a warm gold-to-rainbow iridescent sheen with fine gold glitter, '
                  'like a premium secret-rare trading-card foil border)'),
        'series': "a black rounded box with a polished gold foil edge, 'SERIES' in white and the number in shiny gold",
        'tag': "a small polished gold foil tag reading 'SECRET' in black capitals",
        'word': 'SECRET',
    },
}

TITI = ("the red-and-white striped traffic-cone plush mascot with the silver reflective honeycomb bands, the cute face with rosy "
        "cheeks, round black arms and black mitten hands, the black 'DRIVE SAFE' sash (DRIVE in white, SAFE in red) with the little "
        "house-and-heart icon, and the two big round black wheel feet with red-and-white rims and the white-and-red TTSPOT logo on "
        "each wheel face")

REMOVE_COMMON = ("the 'MALAYSIA'S CAR COMMUNITY IN ONE PLACE' text block in the top-right, the 'DRIVE CONNECT EXPLORE TOGETHER' "
                 "list on the left, every handwritten script note, the thin rule under the short line, the checkered-flag bands, "
                 "the little burst/spark marks, the four-point sparkle stars, the globe grid, and the coloured shapes on the frame")

# Pale v3 background tints: (top, bottom) of the soft vertical gradient. Also used to blank the
# panel of the frame-only reference, so the model sees the target tint.
TINT = {
    'c1': ((253, 245, 245), (248, 224, 224)),  # red
    'c2': ((255, 245, 242), (251, 224, 216)),  # coral pink
    'c3': ((249, 246, 254), (234, 226, 249)),  # lilac
    'c4': ((243, 249, 255), (220, 236, 251)),  # sky blue
    'c5': ((253, 249, 242), (242, 231, 212)),  # warm beige
    'c6': ((243, 251, 247), (219, 241, 230)),  # mint green
    'c7': ((253, 250, 241), (243, 231, 200)),  # soft champagne gold
}

CARDS = {
    'c1': {
        'tier': 'common', 'no': '01', 'name': "'Welcoming Friends'",
        'title': ('WELCOMING', 'FRIENDS'), 'accent': 'red', 'line': 'Find your circle.',
        'figure': ("sitting on the ground with his two big wheel feet forward, giving a thumbs up with his hand on the left of the "
                   "image and holding the small red TTSPOT pennant flag on a black stick upright in his hand on the right of the "
                   "image; he winks (the eye on the left of the image closed in a wink, the other eye open and shiny) with a big "
                   "open happy smile"),
        'bg': ("a very pale blush-red tint, almost white: a smooth soft gradient from near-white at the top to a light rosy red "
               "lower down, with just ONE faint large motif: a soft wide winding road curve sweeping across the lower part behind "
               "him, in a slightly deeper pale rose"),
        'remove': '',
    },
    'c2': {
        'tier': 'common', 'no': '02', 'name': "'Offering Blessings'",
        'title': ('OFFERING', 'BLESSINGS'), 'accent': 'red', 'line': 'Good people. Great journeys.',
        'figure': ("sitting on the ground with his two big wheel feet forward, holding the white gift box with the red ribbon bow "
                   "and the TTSPOT logo in front of his chest with both hands; happy face with both eyes closed in smiling arcs "
                   "and an open smile"),
        'bg': ("a very pale coral-pink tint, almost white: a smooth soft gradient from near-white at the top to a light coral pink "
               "lower down, with just two faint large soft hearts behind him (one on each side), in a slightly deeper pale coral"),
        'remove': ', the small hearts, and the winding road',
    },
    'c3': {
        'tier': 'common', 'no': '03', 'name': "'Striking Poses'",
        'title': ('STRIKING', 'POSES'), 'accent': 'purple', 'line': 'Same TiTi. Different vibes.',
        'figure': ("sitting on the ground with his two big wheel feet forward, wearing the red sunglasses, both hands raised in "
                   "cool 'finger guns' (index fingers pointing, thumbs up), a small confident closed-mouth smile"),
        'bg': ("a very pale lilac tint, almost white: a smooth soft gradient from near-white at the top to a light lilac lower "
               "down, with just ONE faint large motif: a soft wide winding road curve sweeping across the lower part behind him, "
               "in a slightly deeper pale lilac"),
        'remove': '',
    },
    'c4': {
        'tier': 'common', 'no': '04', 'name': "'Taking Photos'",
        'title': ('TAKING', 'PHOTOS'), 'accent': 'bright sky blue', 'line': 'Find the spot. Capture the moment.',
        'figure': ("sitting on the ground with his two big wheel feet forward, holding the black TTSPOT mirrorless camera up to his "
                   "face with both hands, the lens pointing at the viewer, his other eye peeking out beside the camera"),
        'bg': ("a very pale sky-blue tint, almost white: a smooth soft gradient from near-white at the top to a light sky blue "
               "lower down, with just two faint large motifs in a slightly deeper pale blue: a softly curving film strip behind "
               "him on the right and a soft wide winding road curve across the lower part"),
        'remove': ', the map pin, the camera icon',
    },
    'c5': {
        'tier': 'rare', 'no': '05', 'name': "'Waiting for the Meet'",
        'title': ('WAITING', 'FOR THE MEET'), 'accent': 'red', 'line': 'Good cars. Greater company.',
        'figure': ("sitting on the ground with his two big wheel feet forward, holding the white TTSPOT takeaway coffee cup in his "
                   "hand on the left of the image; happy face with both eyes closed in smiling arcs and a big open smile; the glossy "
                   "black full-face helmet with the TTSPOT logo on the ground right beside him on the right of the image, and the "
                   "black square sign reading 'MEET UP' with a white arrow on a short black post standing behind the helmet"),
        'bg': ("a very pale warm-beige tint, almost white: a smooth soft gradient from warm near-white at the top to a light warm "
               "beige lower down, with just two faint large motifs in a slightly deeper pale beige: the city skyline silhouette in "
               "the upper background and a soft wide winding road curve across the lower part"),
        'remove': ', the flyover',
    },
    'c6': {
        'tier': 'rare', 'no': '06', 'name': "'Helping on the Road'",
        'title': ('HELPING', 'ON THE ROAD'), 'accent': 'green', 'line': 'Safer drives. Brighter journeys.',
        'figure': ("sitting on the ground with his two big wheel feet forward, giving a thumbs up with his hand on the left of the "
                   "image and holding the silver wrench in his hand on the right of the image; he winks (the eye on the right of the "
                   "image closed, the other eye open and shiny) with a small smile; the red-and-black TTSPOT toolbox on the ground "
                   "beside him on the left of the image and the red warning triangle standing on the ground beside him on the right"),
        'bg': ("a very pale mint-green tint, almost white: a smooth soft gradient from near-white at the top to a light mint green "
               "lower down, with just ONE faint large motif: a soft wide winding road curve sweeping across the lower part behind "
               "him, in a slightly deeper pale mint"),
        'remove': ', the green road sign with the arrow',
    },
    'c7': {
        'tier': 'secret', 'no': '07', 'name': "'Built for a Better Drive' (the TT Spot x TypeOne collaboration card)",
        'title': ('BUILT FOR A', 'BETTER DRIVE'), 'accent': 'shiny metallic gold', 'line': 'Stable drives. Stronger journeys.',
        'figure': ("in the same low kneeling crouch as in the first image (the wheel foot on the left of the image planted in front, "
                   "the other leg bent under him), gripping the long glossy blue TypeOne strut bar diagonally across his body with "
                   "both hands, the 'TYPEONE' wordmark and the small label on the bar as in the first image; determined, confident "
                   "face with angled brows and a small smile"),
        'bg': ("a very pale soft champagne-gold tint, almost white: a smooth soft gradient from warm near-white at the top to a "
               "light champagne gold lower down, a soft warm glow behind him and just ONE faint large motif: a soft wide road curve "
               "across the lower part in a slightly deeper pale champagne"),
        'remove': None,  # c7 has its own list, see prompt()
    },
}


def prompt(k):
    c = CARDS[k]
    t = TIERS[c['tier']]
    l1, l2 = c['title']
    if k == 'c7':
        title = (f"Move the title to the bottom-left like the rest of the series and restyle it as the series' big chunky rounded "
                 f"sticker title with a thick white sticker outline: '{l1}' on the first line in black and '{l2}' on the second "
                 f"line in {c['accent']} with a thin dark outline so it reads on the pale background, and a short gold brush "
                 f"swoosh under it.")
        remove = ("the dark garage, the car, the posters and signs, the red neon lights, the round display podium and the "
                  "'TYPEONE / THE PROVEN STABLE BAR' text on it, the 'OFFICIALLY SUPPORTED BY TYPEONE' line, the 'SECRET VERSION "
                  "07' box, the handwritten notes, the row of three icons with captions, the 'TTSPOT x TYPEONE DRIVE SAFE ALWAYS' "
                  "small print and the 'TITI GO FURTHER TOGETHER' signature")
        corner = ("THE WHOLE TOP BAND: remove the TTSPOT logo, the '×' and the TYPEONE badge at the top and leave the entire top "
                  "band of the artwork (about the top eighth of the card) completely empty: plain smooth pale background, nothing "
                  "drawn there (the co-branding logos are added afterwards). TiTi's head stays below that band.")
        figure_keep = (f"TiTi: {TITI}, {c['figure']}. REMOVE THE PODIUM: he kneels directly on the pale ground of the scene with "
                       f"a soft contact shadow, no display base, no plinth, no platform. Keep his size and the camera angle.")
        text_extra = ", the 'TYPEONE' wordmark and the small label on the bar"
    else:
        title = (f"The big chunky sticker title in the bottom-left exactly as in the first image: '{l1}' on the first line in black "
                 f"and '{l2}' on the second line in {c['accent']}, the same font, thick white sticker outline, swoosh and position.")
        remove = REMOVE_COMMON + c['remove']
        corner = ("TOP-LEFT CORNER: remove the TTSPOT logo and leave the top-left corner of the artwork completely empty: plain "
                  "smooth pale background, nothing drawn there (the logo is added afterwards).")
        figure_keep = (f"TiTi: {TITI}, {c['figure']}. Exactly the same pose, face, expression, props, position, size and camera "
                       f"angle as in the first image. He sits directly on the ground of the scene with a soft contact shadow, as in "
                       f"the first image: no display base, no plinth, no platform.")
        text_extra = ", 'MEET UP' on the sign" if k == 'c5' else ''
    return (
        f"Edit the first reference image, card {c['no']} {c['name']} of the TT Spot 'TiTi' blind-box collectible card series, "
        f"into the series' new card design. The second reference image is a frame template: take from it ONLY the card frame, "
        f"the '{t['word']}' tag and the SERIES box in the bottom-right corner (its artwork panel is intentionally empty).\n\n"
        f"KEEP EXACTLY AS IN THE FIRST IMAGE, do not redraw or restyle: {figure_keep} Same colours, proportions and soft flocked "
        f"plush texture. {title}\n\n"
        f"CHANGE ONLY THIS:\n"
        f"1. FRAME: {t['frame']}, exactly as on the second image, with the same slightly rounded artwork panel inside it.\n"
        f"2. BACKGROUND: {c['bg']}. Pale, clean and airy; soft even studio light.\n"
        f"3. REMOVE: {remove}.\n"
        f"4. {corner}\n"
        f"5. BOTTOM-RIGHT: the SERIES box exactly as on the second image: {t['series']}, 'SERIES' in small capitals and a big "
        f"bold '{c['no']}' below it with a short underline, and {t['tag']} directly above the box.\n"
        f"6. UNDER THE TITLE: one short line in a clean small dark-grey sans-serif: '{c['line']}'.\n\n"
        f"ONLY THIS TEXT on the whole card: the title, the one short line, '{t['word']}', 'SERIES {c['no']}', 'DRIVE SAFE' on "
        f"the sash and the small TTSPOT logos on the wheels and props{text_extra}. No other words: no taglines, no handwritten "
        f"notes, no lists, no small print. All text crisp and correctly spelled."
    )


PROMPTS = {k: prompt(k) for k in CARDS}


# ---------------------------------------------------------------- frame-only references

# The v2 artwork panel (a rounded rectangle inside the frame) and the bottom-right block that
# holds the tier tag and the SERIES box, measured on design/cards_v2/c*.jpg.
PANEL = (24, 23, 743, 1122)
PANEL_R = 28
CORNER = (596, 900)  # x, y where the tag + SERIES block starts
CORNER_Y = {'c6': 930}  # v2 c6 has a bit of the green title swoosh just above its RARE tag


def gradient(size, top, bottom):
    from PIL import Image
    w, h = size
    g = Image.new('RGB', (1, h))
    for y in range(h):
        f = y / max(1, h - 1)
        g.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * f) for i in range(3)))
    return g.resize((w, h))


def frame_ref(k):
    """The v2 card with its artwork panel repainted in the v3 pale tint, keeping the frame and the
    tag + SERIES block. In the block, each row is kept from the first frame-like pixel onwards
    (bright and unsaturated: white, grey, silver; on c7 any bright pixel: the gold edges), so the
    v2 panel colour does not show around the notch."""
    from PIL import Image, ImageDraw
    im = Image.open(os.path.join(V2, k + '.jpg')).convert('RGB')
    s = 4
    mask = Image.new('L', (CARD[0] * s, CARD[1] * s), 0)
    ImageDraw.Draw(mask).rounded_rectangle(tuple(v * s for v in PANEL), PANEL_R * s, fill=255)
    mask = mask.resize(CARD, Image.LANCZOS)
    px, mp = im.load(), mask.load()
    x0, y0 = CORNER[0], CORNER_Y.get(k, CORNER[1])
    for y in range(y0, CARD[1]):
        first = None
        for x in range(x0, PANEL[2]):
            r, g, b = px[x, y]
            if (r + g + b) / 3 > 150 and (k == 'c7' or max(r, g, b) - min(r, g, b) < 60):
                first = x
                break
        start = first if first is not None else PANEL[2]
        for x in range(start, CARD[0]):
            mp[x, y] = 0
    fill = gradient(CARD, *TINT[k])
    im.paste(fill, (0, 0), mask)
    dst = os.path.join(OUT, f'ref_{k}.png')
    im.save(dst)
    return dst


# ---------------------------------------------------------------- generation

def run(jobs, force=False):
    tasks = {}
    for k, (p, refs, ar) in jobs.items():
        raw = os.path.join(OUT, k + '.png')
        if os.path.exists(raw):
            if not force:
                print('skip (exists)', k, flush=True)
                continue
            n = 1
            while os.path.exists(os.path.join(OUT, f'{k}.v{n}.png')):
                n += 1
            shutil.move(raw, os.path.join(OUT, f'{k}.v{n}.png'))
        inp = {'prompt': p, 'input_urls': refs, 'aspect_ratio': ar, 'resolution': '1K'}
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
    for _ in range(120):
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


# ---------------------------------------------------------------- output

def fit(im):
    """Scale to the card size (centre-crop if the aspect differs)."""
    from PIL import Image
    tw, th = CARD
    s = max(tw / im.width, th / im.height)
    im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    l, t = (im.width - tw) // 2, (im.height - th) // 2
    return im.crop((l, t, l + tw, t + th))


def resize_rgba(im, size):
    """Resize with premultiplied alpha (no dark or light fringes on the edges)."""
    from PIL import Image
    return im.convert('RGBa').resize(size, Image.LANCZOS).convert('RGBA')


# The logo on the v1 cards: its ink spans x 50..207, y 49..150 on every card (measured). The
# brand PNG's ink box is (64, 292, 1041, 960), 977 x 668, so a width of 156 px puts the same
# mark at the same place with a 50 px left margin and a 48 px top margin.
LOGO_INK = (64, 292, 1041, 960)
LOGO_AT = (50, 48)
LOGO_W = 156


def logo_layer():
    from PIL import Image
    lg = Image.open(LOGO).convert('RGBA').crop(LOGO_INK)
    return resize_rgba(lg, (LOGO_W, round(LOGO_W * lg.height / lg.width)))


def typeone_badge():
    """The TypeOne badge cropped from design/cards_v1/c7.jpg: the italic (slanted) rounded rectangle
    with the white outline, blue 'TYPE' and red 'ONE', cut out with an anti-aliased mask so it sits on
    any background. Measured on the v1 card: top edge y=57, bottom y=110, and at mid-height
    (y=83.5) the outline's outer edge runs from x=408 to x=641, both sides leaning right by 0.258 px
    per px going up. The mask is a rounded rectangle drawn unslanted (8x) and sheared to match,
    inset 0.7 px so no dark background shows at the edge."""
    from PIL import Image, ImageDraw
    src = Image.open(os.path.join(V1, 'c7.jpg')).convert('RGB')
    bx0, by0, bx1, by1 = BADGE_BOX
    crop = src.crop(BADGE_BOX).convert('RGBA')
    w, h = crop.size
    s, k, mid = 8, BADGE_SLANT, 83.5 - by0
    m = Image.new('L', (w * s, h * s), 0)
    l, t, r, b = 408 - bx0 + 0.7, 57 - by0 + 0.7, 641 - bx0 - 0.7, 110 - by0 - 0.7
    ImageDraw.Draw(m).rounded_rectangle((l * s, t * s, r * s, b * s), BADGE_R * s, fill=255)
    # output (x, y) samples the unslanted mask at (x + k * (y - mid), y)
    m = m.transform(m.size, Image.AFFINE, (1, k, -k * mid * s, 0, 1, 0), resample=Image.BICUBIC)
    crop.putalpha(m.resize((w, h), Image.LANCZOS))
    return crop.crop(crop.getchannel('A').point(lambda v: 255 if v > 8 else 0).getbbox())


BADGE_BOX = (398, 54, 652, 113)
BADGE_SLANT = 0.258
BADGE_R = 6


def paste_logo(im, k):
    from PIL import Image, ImageDraw, ImageFont
    lg = logo_layer()
    im = im.convert('RGBA')
    im.alpha_composite(lg, LOGO_AT)
    if k == 'c7':
        # co-branding row: logo, '×', badge, vertically centred on the TT mark (not the wordmark)
        mark_h = round((821 - 292) / (LOGO_INK[3] - LOGO_INK[1]) * lg.height)
        cy = LOGO_AT[1] + mark_h // 2 + 6
        x = LOGO_AT[0] + lg.width + 22
        # the '×': two anti-aliased strokes drawn 8x and scaled down
        s, size, wgt = 8, 22, 3
        layer = Image.new('L', ((size + 4) * s, (size + 4) * s), 0)
        d = ImageDraw.Draw(layer)
        a, b = 2 * s, (size + 2) * s
        d.line((a, a, b, b), fill=255, width=wgt * s)
        d.line((a, b, b, a), fill=255, width=wgt * s)
        layer = layer.resize((size + 4, size + 4), Image.LANCZOS)
        ink = Image.new('RGBA', layer.size, (40, 36, 30, 255))
        ink.putalpha(layer)
        im.alpha_composite(ink, (x, cy - layer.height // 2))
        x += layer.width + 22
        badge = typeone_badge()
        bh = BADGE_H
        badge = resize_rgba(badge, (round(badge.width * bh / badge.height), bh))
        im.alpha_composite(badge, (x, cy - bh // 2))
    return im.convert('RGB')


BADGE_H = 53  # the badge at its v1 size (it was 53 px tall on the 768-wide v1 card)


def plain(box, feather=10):
    """Repaint a box as plain smooth background: a Coons patch built from the pixels just outside
    its four edges (each edge colour averaged over a 5 px strip, then smoothed), blended in with a
    feathered edge. For the pale gradients only; used where the model left marks behind the logo."""
    def fix(im):
        from PIL import Image, ImageDraw, ImageFilter
        x0, y0, x1, y1 = box
        w, h = x1 - x0, y1 - y0
        blur = im.filter(ImageFilter.BoxBlur(3))
        px = blur.load()
        top = [px[x0 + i, max(0, y0 - 4)] for i in range(w)]
        bot = [px[x0 + i, min(im.height - 1, y1 + 3)] for i in range(w)]
        lef = [px[max(0, x0 - 4), y0 + j] for j in range(h)]
        rig = [px[min(im.width - 1, x1 + 3), y0 + j] for j in range(h)]
        c00, c10, c01, c11 = top[0], top[-1], bot[0], bot[-1]
        patch = Image.new('RGB', (w, h))
        pp = patch.load()
        for j in range(h):
            v = j / max(1, h - 1)
            for i in range(w):
                u = i / max(1, w - 1)
                pp[i, j] = tuple(round(
                    (1 - v) * top[i][c] + v * bot[i][c] + (1 - u) * lef[j][c] + u * rig[j][c]
                    - ((1 - u) * (1 - v) * c00[c] + u * (1 - v) * c10[c] + (1 - u) * v * c01[c] + u * v * c11[c]))
                    for c in range(3))
        patch = patch.filter(ImageFilter.GaussianBlur(2))
        mask = Image.new('L', (w, h), 0)
        ImageDraw.Draw(mask).rectangle((feather // 2, feather // 2, w - 1 - feather // 2, h - 1 - feather // 2), fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(feather / 3))
        im.paste(patch, (x0, y0), mask)
        return im
    return fix


def recolour_green(box, sample):
    """c6: the model kept a dark-green sliver between the RARE tag and the frame (and a speck by
    the SERIES box corner), a bit of v2's green title swoosh that survived in the frame reference.
    Inside box, pixels clearly greener than the mint background are repainted with the background
    colour (the mean of the sample box), through a slightly grown and softened mask."""
    def fix(im):
        from PIL import Image, ImageFilter
        x0, y0, x1, y1 = box
        region = im.crop(box)
        px = region.load()
        m = Image.new('L', region.size, 0)
        mp = m.load()
        for y in range(region.height):
            for x in range(region.width):
                r, g, b = px[x, y]
                if g - r > 45 and (r + g + b) / 3 < 185:
                    mp[x, y] = 255
        m = m.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
        bg = im.crop(sample).resize((1, 1), Image.BOX).getpixel((0, 0))
        region.paste(bg, (0, 0), m)
        im.paste(region, (x0, y0))
        return im
    return fix


def clean_tag(plate, pill, chamfer, sample_y):
    """c7: the SECRET pill came out sitting on a dark gold-foil plate (black streaks above it), a
    leftover of the dark v2 card behind the tag in the frame reference. Repaint the plate around
    the pill with the pale background (per column, the colour just above the plate, smoothed) and
    keep the gold pill (a chamfered rectangle) as it is."""
    def fix(im):
        from PIL import Image, ImageDraw, ImageFilter
        x0, y0, x1, y1 = plate
        w, h = x1 - x0, y1 - y0
        blur = im.filter(ImageFilter.BoxBlur(2)).load()
        cols = [tuple(sum(blur[x, sample_y - d][c] for d in range(3)) // 3 for c in range(3)) for x in range(x0, x1)]
        patch = Image.new('RGB', (w, h))
        pp = patch.load()
        for i, col in enumerate(cols):
            for j in range(h):
                pp[i, j] = col
        patch = patch.filter(ImageFilter.BoxBlur(3))
        s = 4
        mask = Image.new('L', (w * s, h * s), 0)
        d = ImageDraw.Draw(mask)
        d.rectangle((0, 0, w * s, h * s), fill=255)
        px0, py0, px1, py1 = ((pill[0] - x0) * s, (pill[1] - y0) * s, (pill[2] - x0) * s, (pill[3] - y0) * s)
        c = chamfer * s
        d.polygon([(px0 + c, py0), (px1 - c, py0), (px1, py0 + c), (px1, py1 - c), (px1 - c, py1), (px0 + c, py1),
                   (px0, py1 - c), (px0, py0 + c)], fill=0)
        mask = mask.resize((w, h), Image.LANCZOS)
        im.paste(patch, (x0, y0), mask)
        return im
    return fix


# Pillow fixes on the finished 768x1152 cards (before the logo goes on), after reviewing each image.
FIXES = {
    'c6': [recolour_green((718, 924, 746, 1000), (700, 905, 720, 925))],
    'c7': [clean_tag((604, 897, 740, 959), (611.5, 915.5, 730, 954), 4.5, 894)],
}


def install():
    from PIL import Image
    os.makedirs(DST, exist_ok=True)
    for k in sorted(CARDS):
        raw = os.path.join(OUT, k + '.png')
        if not os.path.exists(raw):
            print('missing', k, flush=True)
            continue
        im = fit(Image.open(raw).convert('RGB'))
        for fix in FIXES.get(k, []):
            im = fix(im)
        im = paste_logo(im, k)
        dst = os.path.join(DST, k + '.jpg')
        im.save(dst, quality=86, optimize=True, progressive=True)  # as the v1/v2 cards (~q86)
        print('installed', os.path.relpath(dst, REPO), Image.open(dst).size, os.path.getsize(dst), 'bytes', flush=True)


NAMES = {
    'c1': ('01', 'Welcoming Friends', 'COMMON'), 'c2': ('02', 'Offering Blessings', 'COMMON'),
    'c3': ('03', 'Striking Poses', 'COMMON'), 'c4': ('04', 'Taking Photos', 'COMMON'),
    'c5': ('05', 'Waiting for the Meet', 'RARE'), 'c6': ('06', 'Helping on the Road', 'RARE'),
    'c7': ('07', 'Built for a Better Drive', 'SECRET'),
}
TIER_INK = {'COMMON': (120, 124, 130), 'RARE': (110, 128, 150), 'SECRET': (184, 138, 20)}


def _font(name, size):
    from PIL import ImageFont
    try:
        return ImageFont.truetype('C:/Windows/Fonts/' + name, size)
    except OSError:
        return ImageFont.load_default()


def _row(im, d, folder, y, cw, ch, left, gap, labels=True):
    from PIL import Image
    for i, k in enumerate(sorted(NAMES)):
        x = left + i * (cw + gap)
        card = Image.open(os.path.join(folder, k + '.jpg')).convert('RGB').resize((cw, ch), Image.LANCZOS)
        im.paste(card, (x, y))
        d.rectangle((x - 1, y - 1, x + cw, y + ch), outline=(215, 215, 215))
        if labels:
            no, name, tier = NAMES[k]
            d.text((x, y + ch + 16), f'{no}  {name}', font=_font('segoeuib.ttf', 22), fill=(20, 20, 20))
            d.text((x, y + ch + 48), tier, font=_font('seguibl.ttf', 18), fill=TIER_INK[tier])


def sheets():
    """design/cards_v3/lineup.jpg (the seven v3 cards in one row) and compare.jpg (v1 / v2 / v3 rows)."""
    from PIL import Image, ImageDraw
    cw, ch, gap, pad, top = 360, 540, 24, 48, 130
    n = len(NAMES)
    bg, ink, sub = (246, 246, 246), (20, 20, 20), (110, 110, 110)

    W = pad * 2 + n * cw + (n - 1) * gap
    im = Image.new('RGB', (W, top + ch + 90 + pad), bg)
    d = ImageDraw.Draw(im)
    d.text((pad, 36), 'TT Spot blind-box cards, series v3: v1 TiTi, v2 frames, pale backgrounds', font=_font('seguibl.ttf', 40), fill=ink)
    d.text((pad, 88), '4 common (white frame)  ·  2 rare (silver holo)  ·  1 secret (gold holo)  ·  logo composited from assets/brand/logo.png', font=_font('segoeui.ttf', 22), fill=sub)
    _row(im, d, DST, top, cw, ch, pad, gap)
    dst = os.path.join(DST, 'lineup.jpg')
    im.save(dst, quality=88, optimize=True, progressive=True)
    print('sheet', os.path.relpath(dst, REPO), im.size, os.path.getsize(dst), 'bytes', flush=True)

    left = pad + 90
    W2 = left + n * cw + (n - 1) * gap + pad
    rows = ((V1, 'v1'), (V2, 'v2'), (DST, 'v3'))
    rh = ch + 40
    im = Image.new('RGB', (W2, top + 3 * rh + 50 + pad), bg)
    d = ImageDraw.Draw(im)
    d.text((pad, 36), 'TT Spot blind-box cards: v1, v2, v3', font=_font('seguibl.ttf', 40), fill=ink)
    d.text((pad, 88), 'v1 as first shipped  ·  v2 one frame system, standing on display bases  ·  v3 v1 figures in the v2 frames, pale backgrounds, real logo', font=_font('segoeui.ttf', 22), fill=sub)
    for i, (folder, lab) in enumerate(rows):
        y = top + i * rh
        d.text((pad, y + ch // 2 - 24), lab, font=_font('seguibl.ttf', 40), fill=ink)
        _row(im, d, folder, y, cw, ch, left, gap, labels=False)
    y = top + 3 * rh - 30
    for i, k in enumerate(sorted(NAMES)):
        no, name, tier = NAMES[k]
        x = left + i * (cw + gap)
        d.text((x, y), f'{no}  {name}', font=_font('segoeuib.ttf', 22), fill=ink)
        d.text((x, y + 30), tier, font=_font('seguibl.ttf', 18), fill=TIER_INK[tier])
    dst = os.path.join(DST, 'compare.jpg')
    im.save(dst, quality=88, optimize=True, progressive=True)
    print('sheet', os.path.relpath(dst, REPO), im.size, os.path.getsize(dst), 'bytes', flush=True)


def ship():
    """Copy the v3 cards into assets/cards/ (v1 stays in design/cards_v1/, v2 in design/cards_v2/)."""
    for k in sorted(NAMES):
        live = os.path.join(REPO, 'assets', 'cards', k + '.jpg')
        shutil.copyfile(os.path.join(DST, k + '.jpg'), live)
        print('shipped', os.path.relpath(live, REPO), os.path.getsize(live), 'bytes', flush=True)


if __name__ == '__main__':
    args = sys.argv[1:]
    if '--print' in args:
        for k, p in PROMPTS.items():
            print(f'== {k} ==\n{p}\n')
        sys.exit()
    if '--refs' in args:
        for k in CARDS:
            print('ref', os.path.relpath(frame_ref(k), REPO), flush=True)
        sys.exit()
    if '--install' in args:
        install()
        sys.exit()
    if '--sheets' in args:
        sheets()
        sys.exit()
    if '--ship' in args:
        ship()
        sys.exit()
    force = '--force' in args
    only = {a for a in args if not a.startswith('--')}
    before = credits()
    keys = [k for k in CARDS if not only or k in only]
    jobs = {k: (PROMPTS[k], [upload(os.path.join(V1, k + '.jpg')), upload(frame_ref(k))], '2:3') for k in keys}
    run(jobs, force)
    print('Kie credits:', before, '->', credits(), flush=True)

"""Blind-box cards v2: all seven cards in one design system (the owner's Direction A,
design/rare_concepts/A_c5.jpg and A_c6.jpg, extended to the whole series).

Same on every card: 768x1152, TTSPOT logo top-left, a big two-line sticker title
bottom-left (second line in the card's accent colour), one short line under it, a
SERIES 0N box bottom-right with the rarity tag above it, and TiTi on the same round
glossy black display base, same camera angle and studio light, a soft glow behind
him, one pose + one prop set per card (all different poses), a deeper version of the
card's colour with 2-3 simple motifs. Per tier:

  COMMON 01-04  clean white frame, subtle inner border, pearl base rim, grey COMMON tag
  RARE   05-06  silver holographic foil frame, silver rim, silver RARE tag (= the A concepts)
  SECRET 07     gold holographic foil frame, gold rim, gold SECRET tag, TT SPOT x TYPEONE

Kie GPT Image 2 image-to-image. References: the current card (TiTi, props, theme) and
design/rare_concepts/A_c5.jpg (the approved template: layout, base, camera, light).

  python tool/art_cards_v2.py                 # pass 1: generate every missing raw image (c1-c4, c7)
  python tool/art_cards_v2.py c1 c3           # just some keys
  python tool/art_cards_v2.py --force c3      # regenerate (old raw kept as <key>.v<n>.png)
  python tool/art_cards_v2.py --edit          # pass 2: pose edits (c1, c2 from pass 1; c6 from A_c6), see EDITS
  python tool/art_cards_v2.py --print         # show the prompts
  python tool/art_cards_v2.py --install       # 768x1152 JPGs (+ Pillow fixes) into design/cards_v2/
  python tool/art_cards_v2.py --sheets        # design/cards_v2/lineup.jpg and before_after.jpg
  python tool/art_cards_v2.py --ship          # old assets/cards/c*.jpg -> design/cards_v1/, v2 -> assets/cards/

Raw output: tool/titi_gen/cards_v2/<key>.png (git-ignored). Needs ~/.supabase/ttspot-kie-key.txt
(never commit it). Kie rate-limits bursts (429), so tasks are created ~4 s apart.

What shipped (2026-10-01), 8 images, 60 Kie credits (pass 1: 5 images, 30; pass 2: 3 edits, 30):
  c1  pass 2 edit of pass 1 (pass 1 sat; now stands and waves with the flag)
  c2  pass 2 edit of pass 1 (pass 1 sat and was coral-red with a white tab behind the logo;
      now stands holding the gift out, pink background, plain panel)
  c3  pass 1 (leans on one wheel, other kicked out, peace sign)
  c4  pass 1 (kneels with the camera up)
  c5  design/rare_concepts/A_c5.jpg as it is (sits with the coffee)
  c6  pass 2 edit of A_c6 (stands, thumbs up, wrench on the shoulder) + Pillow fix: the edit
      drew a maple leaf in the sash's house icon, repainted as the heart (FIXES)
  c7  pass 1 (power stance with the TypeOne bar)
Every other title, line, tag, series number and logo came out clean, so no text composites.
"""
import json, os, shutil, sys, time, uuid, urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(ROOT)
OUT = os.path.join(ROOT, 'titi_gen', 'cards_v2')
DST = os.path.join(REPO, 'design', 'cards_v2')
V1 = os.path.join(REPO, 'design', 'cards_v1')
os.makedirs(OUT, exist_ok=True)
CARD = (768, 1152)  # assets/cards/c*.jpg
TEMPLATE = 'design/rare_concepts/A_c5.jpg'


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
        'frame': ('a clean white card frame (a white border like the current common cards, slightly rounded outer corners, no foil, '
                  'no rainbow) with a subtle thin light-grey inner border line'),
        'series': 'a white rounded box with a thin light-grey edge',
        'tag': "a small light-grey pill tag reading 'COMMON' in dark-grey capitals",
        'word': 'COMMON',
        'rim': 'pearl-white',
    },
    'secret': {
        'frame': ('a polished gold holographic foil frame (a warm gold-to-rainbow iridescent sheen and fine gold glitter, like a '
                  'premium secret-rare trading-card foil border)'),
        'series': "a black rounded box with a polished gold foil edge, 'SERIES' in white and the number in shiny gold",
        'tag': "a small polished gold foil tag reading 'SECRET' in black capitals",
        'word': 'SECRET',
        'rim': 'polished gold',
    },
}

FIGURE = ("TiTi exactly as in both references: the red-and-white striped traffic-cone mascot with silver reflective bands, the same "
          "cute face with rosy cheeks, round black arms and mitten hands, the black 'DRIVE SAFE' sash (DRIVE in white, SAFE in red) "
          "with the little house-and-heart icon, and two big round black wheel feet with red-and-white rims and the TTSPOT logo; the "
          "same colours, same proportions, same soft flocked plush texture")


def base(rim):
    return (f'one round glossy display base: a short, wide black disc plinth with a thin glossy {rim} rim and a soft mirror '
            f'reflection on its top surface, just big enough for the figure and its props, no text on the base')


CARDS = {
    'c1': {
        'tier': 'common', 'no': '01', 'name': "'Welcoming Friends'",
        'title': ('WELCOMING', 'FRIENDS'), 'accent': 'bright red', 'line': 'Find your circle.',
        'bg': ('a deep, rich crimson and wine red (a richer, deeper version of the red of the current card), with the same faint '
               'globe grid, checkered-flag band and winding road motifs in slightly lighter tones of the same red'),
        'glow': 'warm pinkish-white',
        'pose': ('STANDING upright on his two wheel feet (not sitting), facing the viewer, cheerfully waving hello: his hand on the '
                 'left of the image is raised high with the palm open; his hand on the right of the image holds a small red TTSPOT '
                 'pennant flag on a short black stick, upright beside his head. Winking happy face with a big open smile, as in the '
                 'first reference'),
        'props': 'little TTSPOT flag',
    },
    'c2': {
        'tier': 'common', 'no': '02', 'name': "'Offering Blessings'",
        'title': ('OFFERING', 'BLESSINGS'), 'accent': 'bright coral red', 'line': 'Good people. Great journeys.',
        'bg': ('a deep, rich coral pink and rose (a richer, deeper version of the pale coral of the current card), with the same '
               'large soft hearts, winding road and four-point sparkle motifs in slightly lighter tones of the same coral'),
        'glow': 'peach-white',
        'pose': ('BOWING FORWARD a little while standing on his two wheel feet, holding the white gift box with the red ribbon bow '
                 'and the TTSPOT logo out in front of him towards the viewer with both hands, offering it as a present. Happy face '
                 'with closed smiling eyes and an open smile, as in the first reference'),
        'props': 'gift box',
    },
    'c3': {
        'tier': 'common', 'no': '03', 'name': "'Striking Poses'",
        'title': ('STRIKING', 'POSES'), 'accent': 'vivid purple', 'line': 'Same TiTi. Different vibes.',
        'bg': ('a deep, rich violet and royal purple (a richer, deeper version of the lilac of the current card), with the same '
               'faint globe grid, four-point sparkle stars and checkered-flag motifs in slightly lighter tones of the same purple'),
        'glow': 'lavender-white',
        'pose': ('a cool fashion-model pose: standing on one wheel foot with his whole body LEANING and tilted to one side, the other '
                 'wheel foot lifted and kicked out, one hand on his hip and the other hand making a clear peace sign (V sign) beside '
                 'his face, wearing the red sunglasses, confident smile, as in the first reference'),
        'props': 'red sunglasses',
    },
    'c4': {
        'tier': 'common', 'no': '04', 'name': "'Taking Photos'",
        'title': ('TAKING', 'PHOTOS'), 'accent': 'bright sky blue', 'line': 'Find the spot. Capture the moment.',
        'bg': ('a deep, rich cobalt and azure blue (a richer, deeper version of the light blue of the current card), with the same '
               'faint film strip, map pin and globe grid motifs in slightly lighter tones of the same blue'),
        'glow': 'icy-white',
        'pose': ('CROUCHING low on one knee like a photographer lining up a shot, leaning forward, holding the black TTSPOT mirrorless '
                 'camera up to his eye with both hands, the lens pointing at the viewer, his other eye open and focused, as in the '
                 'first reference'),
        'props': 'camera',
    },
    'c7': {
        'tier': 'secret', 'no': '07', 'name': "'Built for a Better Drive' (the TT Spot x TypeOne collaboration card)",
        'title': ('BUILT FOR A', 'BETTER DRIVE'), 'accent': 'shiny metallic gold', 'line': 'Stable drives. Stronger journeys.',
        'bg': ('a deep black and charcoal night garage showroom (the same black-and-gold mood as the current card), with soft red '
               'neon light strips on the dark walls, a faint glossy floor and a few gold sparkle glints; no car, no signs, no posters'),
        'glow': 'warm golden',
        'pose': ('a heroic POWER STANCE: standing with his wheel feet planted wide apart in a strong lunge, determined confident face '
                 '(as in the first reference), gripping the blue TypeOne strut bar diagonally across his body with both hands. The '
                 'bar is a long glossy blue anodised metal strut brace with bent mounting brackets at both ends and only a small '
                 "'TYPEONE' wordmark on it, no stickers"),
        'props': 'blue TypeOne strut bar',
        'cobrand': ("CO-BRANDING across the top, in one row: the TTSPOT logo top-left (the white-and-red version, as on the first "
                    "reference), a thin '×' and the blue TYPEONE badge logo (a blue rounded rectangle with 'TYPE' in white and 'ONE' "
                    "in red italic capitals, white outline) exactly as on the first reference. Nothing else at the top."),
    },
}


def prompt(k):
    c = CARDS[k]
    t = TIERS[c['tier']]
    l1, l2 = c['title']
    extra = ", the 'TYPEONE' wordmark on the bar and the TYPEONE badge logo" if k == 'c7' else ''
    logo = c.get('cobrand') or ("The TTSPOT logo (the red-and-black 'TT' mark with the small checkered corner and the 'TTSPOT' "
                                "wordmark below it) in the top-left corner inside the frame.")
    return (
        f"Create card {c['no']} {c['name']} of the TT Spot 'TiTi' blind-box collectible card series, redesigned in the series' new "
        f"unified design system. The first reference image is the current version of this card: take TiTi, his props, the theme "
        f"and the background motifs from it. The second reference image is the approved template of the new system (a rare card): "
        f"copy its exact layout, typography style, display base, camera angle, lighting, figure size and card proportions; only the "
        f"frame finish, colours, pose and props differ.\n\n"
        f"LAYOUT (portrait 2:3 card, identical on every card of the series): {t['frame']} around the artwork panel, which has "
        f"slightly rounded corners. {logo} A big, chunky, rounded, heavy bold title in the bottom-left with a thick white sticker "
        f"outline, exactly like the template's title: '{l1}' on the first line in black and '{l2}' on the second line in "
        f"{c['accent']}, with a short {c['accent']} brush swoosh under it. Under the title one short line in a clean small "
        f"sans-serif in white: '{c['line']}'. The SERIES box in the bottom-right corner exactly as in the template: {t['series']}, "
        f"'SERIES' in small capitals and a big bold '{c['no']}' below it with a short {c['accent']} underline. {t['tag'][0].upper() + t['tag'][1:]} "
        f"sits directly above the SERIES box, where the template has its RARE tag.\n\n"
        f"ONLY THIS TEXT on the whole card: the TTSPOT logo, the title, the one short line, '{t['word']}', 'SERIES {c['no']}', "
        f"'DRIVE SAFE' on the sash and the small TTSPOT logos on the wheels and props{extra}. No other words: no taglines, no "
        f"handwritten notes, no lists, no small print. All text crisp and correctly spelled.\n\n"
        f"BACKGROUND: {c['bg']}, with a soft {c['glow']} glow behind TiTi. Simple and uncluttered.\n\n"
        f"THE FIGURE: {FIGURE}. POSE: {c['pose']}. Present it as a collectible figure product shot that could be manufactured as a "
        f"plush pendant or a vinyl figure: TiTi and his {c['props']} on {base(t['rim'])}; one clear pose, a clean readable "
        f"silhouette, every prop held in his hands or standing on the base, nothing floating. The same camera angle as the "
        f"template (slightly from above, three-quarter front view), the same figure size, soft studio lighting with a soft contact "
        f"shadow and a gentle rim light, the figure and base centred in the upper-middle of the card above the title."
    )


PROMPTS = {k: prompt(k) for k in CARDS}


# ---------------------------------------------------------------- pass 2: pose edits
#
# Pass 1 got the system right on every card, but the model fell back to the sitting pose
# of its references on c1 and c2 (c5 and c6 sit too), so the lineup had four sitting
# figures. Pass 2 edits those images, keeping everything but the pose. The first-pass
# raws are kept as tool/titi_gen/cards_v2/c1.v1.png and c2.v1.png. c6 (the A concept) is
# edited the same way so 05 and 06 do not share a pose; A_c6 itself stays as it is.
# Reference 2 is c7's pass-1 raw, the only card where TiTi stands on his legs.

LEGS = ("STANDS upright on the display base instead of sitting: under his cone body two short, stubby red-and-white striped "
        "plush legs, each ending in one of his big round black wheel feet planted flat on the base, the TTSPOT logos on the wheel "
        "faces turned towards the viewer. The second reference image only shows what TiTi's legs look like when he stands: copy "
        "that leg anatomy, nothing else from it (not its pose, props, colours or card)")

KEEP = ("Keep EVERYTHING else exactly the same as the first image: the card frame, the TTSPOT logo, the title, the short line, "
        "the rarity tag, the SERIES box, the background and its motifs, the glow, the round black display base and its rim, the "
        "camera angle, the lighting, and TiTi's face, sash, colours, proportions and plush texture. All text stays crisp and "
        "correctly spelled. One clear pose, a clean silhouette, nothing floating.")

EDITS = {
    'c1': ('tool/titi_gen/cards_v2/c1.v1.png',
           "Edit the first reference image, card 01 'Welcoming Friends' of the TT Spot 'TiTi' blind-box card series. Change only "
           f"TiTi's pose: he {LEGS}. Standing tall and facing the viewer, he waves hello with his hand on the left of the image "
           "raised high, palm open, and holds the small red TTSPOT pennant flag upright in his other hand, as now. Same winking "
           f"happy face. {KEEP}"),
    'c2': ('tool/titi_gen/cards_v2/c2.v1.png',
           "Edit the first reference image, card 02 'Offering Blessings' of the TT Spot 'TiTi' blind-box card series. Three "
           f"changes only. (1) TiTi's pose: he {LEGS}. He bows forward a little from the waist and holds the white TTSPOT gift "
           "box with the red ribbon out in front of him with both hands at belly height, below the sash, offering it to the "
           "viewer, so the whole black 'DRIVE SAFE' sash (DRIVE in white, SAFE in red) is visible. Same happy face with closed "
           "smiling eyes. (2) The artwork panel is a plain rounded rectangle like the rest of the series: remove the white tab "
           "behind the TTSPOT logo so the logo sits directly on the background in the top-left corner. (3) The background "
           "becomes a deeper, richer rose and coral PINK, clearly pink rather than red, keeping the soft hearts, winding road and "
           f"sparkle motifs in lighter pinks. {KEEP}"),
    'c6': ('design/rare_concepts/A_c6.jpg',
           "Edit the first reference image, the RARE card 06 'Helping on the Road' of the TT Spot 'TiTi' blind-box card series. "
           f"Change only TiTi's pose: he {LEGS}. Standing proud like a mechanic after a job well done, he gives a thumbs up with "
           "his hand on the left of the image and rests the silver wrench on his shoulder with his other hand. The red-and-black "
           "TTSPOT toolbox still stands on the base beside him on the left and the red warning triangle beside him on the right. "
           f"Same winking face. {KEEP}"),
}
STANCE_REF = 'tool/titi_gen/cards_v2/c7.png'


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


# Pillow fixes on the finished 768x1152 cards, filled in after reviewing each image.

def heart_icon(house, center, size):
    """The pass-2 edit of c6 drew a maple leaf in the sash's house icon instead of the
    heart. Inside the house box, repaint the leaf's red pixels (and their soft edge)
    with the house's white, then draw the series' red heart (drawn 8x, scaled down)."""
    def fix(im):
        from PIL import Image, ImageDraw, ImageFilter
        x0, y0, x1, y1 = house
        box = im.crop(house)
        px = box.load()
        w, h = box.size
        red = Image.new('L', box.size, 0)
        rp = red.load()
        reds = []
        for y in range(h):
            for x in range(w):
                r, g, b = px[x, y]
                if r > 120 and r - max(g, b) > 60:
                    rp[x, y] = 255
                    reds.append((r, g, b))
        mask = red.filter(ImageFilter.MaxFilter(3))
        whites = sorted((px[x, y] for y in range(h) for x in range(w) if sum(px[x, y]) > 600 and not mask.getpixel((x, y))), key=sum)
        white = whites[len(whites) // 2]
        box.paste(white, (0, 0), mask)
        ink = tuple(sorted(reds, key=lambda c: c[0])[len(reds) // 2])
        s = 8
        cx, cy = center[0] - x0, center[1] - y0
        layer = Image.new('L', (w * s, h * s), 0)
        d = ImageDraw.Draw(layer)
        r = size * s / 4  # two lobes and a point
        d.ellipse((cx * s - 2 * r, cy * s - r, cx * s, cy * s + r), fill=255)
        d.ellipse((cx * s, cy * s - r, cx * s + 2 * r, cy * s + r), fill=255)
        d.polygon([(cx * s - 1.93 * r, cy * s + 0.45 * r), (cx * s + 1.93 * r, cy * s + 0.45 * r), (cx * s, cy * s + 2.3 * r)], fill=255)
        box.paste(ink, (0, 0), layer.resize((w, h), Image.LANCZOS))
        im.paste(box, (x0, y0))
        return im
    return fix


FIXES = {'c6': [heart_icon((500, 512, 530, 546), (515, 529), 15)]}


def install():
    from PIL import Image
    os.makedirs(DST, exist_ok=True)
    srcs = {k: os.path.join(OUT, k + '.png') for k in CARDS}
    srcs['c5'] = os.path.join(REPO, 'design', 'rare_concepts', 'A_c5.jpg')
    srcs['c6'] = os.path.join(OUT, 'c6.png')  # the pass-2 edit of A_c6
    if not os.path.exists(srcs['c6']):
        srcs['c6'] = os.path.join(REPO, 'design', 'rare_concepts', 'A_c6.jpg')
    for k in sorted(srcs):
        if not os.path.exists(srcs[k]):
            print('missing', k, flush=True)
            continue
        dst = os.path.join(DST, k + '.jpg')
        im = Image.open(srcs[k])
        if srcs[k].endswith('.jpg') and im.size == CARD and not FIXES.get(k):
            shutil.copyfile(srcs[k], dst)  # already a finished card: no second JPEG pass
        else:
            im = fit(im.convert('RGB'))
            for fix in FIXES.get(k, []):
                im = fix(im)
            im.save(dst, quality=86, optimize=True, progressive=True)  # as the v1 cards (~q86)
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
    """design/cards_v2/lineup.jpg (the seven v2 cards in one row) and before_after.jpg (v1 row over v2 row)."""
    from PIL import Image, ImageDraw
    cw, ch, gap, pad, top = 360, 540, 24, 48, 130
    n = len(NAMES)
    W = pad * 2 + n * cw + (n - 1) * gap
    bg, ink, sub = (246, 246, 246), (20, 20, 20), (110, 110, 110)

    im = Image.new('RGB', (W, top + ch + 90 + pad), bg)
    d = ImageDraw.Draw(im)
    d.text((pad, 36), 'TT Spot blind-box cards, series v2: one design system', font=_font('seguibl.ttf', 40), fill=ink)
    d.text((pad, 88), '4 common (white frame, pearl rim)  ·  2 rare (silver holo, silver rim)  ·  1 secret (gold holo, gold rim)', font=_font('segoeui.ttf', 22), fill=sub)
    _row(im, d, DST, top, cw, ch, pad, gap)
    dst = os.path.join(DST, 'lineup.jpg')
    im.save(dst, quality=88, optimize=True, progressive=True)
    print('sheet', os.path.relpath(dst, REPO), im.size, os.path.getsize(dst), 'bytes', flush=True)

    left = pad + 90
    W2 = left + n * cw + (n - 1) * gap + pad
    im = Image.new('RGB', (W2, top + 2 * ch + 60 + 90 + pad), bg)
    d = ImageDraw.Draw(im)
    d.text((pad, 36), 'TT Spot blind-box cards: before and after', font=_font('seguibl.ttf', 40), fill=ink)
    d.text((pad, 88), 'Top: v1 (as shipped).  Bottom: v2 (one system, figure on a display base).', font=_font('segoeui.ttf', 22), fill=sub)
    y1, y2 = top, top + ch + 60
    for y, lab in ((y1, 'v1'), (y2, 'v2')):
        d.text((pad, y + ch // 2 - 24), lab, font=_font('seguibl.ttf', 40), fill=ink)
    _row(im, d, V1, y1, cw, ch, left, gap, labels=False)
    _row(im, d, DST, y2, cw, ch, left, gap)
    dst = os.path.join(DST, 'before_after.jpg')
    im.save(dst, quality=88, optimize=True, progressive=True)
    print('sheet', os.path.relpath(dst, REPO), im.size, os.path.getsize(dst), 'bytes', flush=True)


def ship():
    """Keep the shipped cards in design/cards_v1/ (once), then copy the v2 cards into assets/cards/."""
    os.makedirs(V1, exist_ok=True)
    for k in sorted(NAMES):
        live = os.path.join(REPO, 'assets', 'cards', k + '.jpg')
        old = os.path.join(V1, k + '.jpg')
        if not os.path.exists(old):
            shutil.copyfile(live, old)
            print('kept', os.path.relpath(old, REPO), flush=True)
        shutil.copyfile(os.path.join(DST, k + '.jpg'), live)
        print('shipped', os.path.relpath(live, REPO), os.path.getsize(live), 'bytes', flush=True)


if __name__ == '__main__':
    args = sys.argv[1:]
    if '--print' in args:
        for k, p in PROMPTS.items():
            print(f'== {k} ==\n{p}\n')
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
    if '--edit' in args:  # pass 2: python tool/art_cards_v2.py --edit [c1 c2 c6]
        stance = upload(os.path.join(REPO, STANCE_REF))
        keys = [k for k in EDITS if not only or k in only]
        run({k: (EDITS[k][1], [upload(os.path.join(REPO, EDITS[k][0])), stance], '2:3') for k in keys}, force)
        print('Kie credits:', before, '->', credits(), flush=True)
        sys.exit()
    template = upload(os.path.join(REPO, TEMPLATE))
    keys = [k for k in CARDS if not only or k in only]
    # the v1 card is the reference (design/cards_v1/ once --ship has replaced assets/cards/)
    v1 = lambda k: os.path.join(V1 if os.path.exists(os.path.join(V1, k + '.jpg')) else os.path.join(REPO, 'assets', 'cards'), k + '.jpg')
    jobs = {k: (PROMPTS[k], [upload(v1(k)), template], '2:3') for k in keys}
    run(jobs, force)
    after = credits()
    print('Kie credits:', before, '->', after, flush=True)

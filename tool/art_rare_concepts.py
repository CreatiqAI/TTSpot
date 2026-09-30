"""Rare-tier concept art for blind-box cards 05 and 06 (concepts only, not used by the app).

Two directions, each applied to both rare cards, so four images:
  A  "Rare frame": same plush TiTi and scene, silver holo foil frame, RARE foil tag,
     deeper background colour, subtle sparkle, far less small text, TiTi on a round
     glossy display base.
  B  "Special-finish figure": the same frame upgrades, and TiTi rendered as a
     special-finish vinyl figure variant (05 champagne-bronze metallic stripes,
     06 emerald pearlescent stripes), studio product-shot lighting.

Kie GPT Image 2 image-to-image, references = the current card + common card 01.

  python tool/art_rare_concepts.py                 # generate every missing raw image
  python tool/art_rare_concepts.py A_c5 B_c6       # just some keys
  python tool/art_rare_concepts.py --force A_c5    # regenerate (old raw kept as <key>.v<n>.png)
  python tool/art_rare_concepts.py --install       # 768x1152 JPGs into design/rare_concepts/
  python tool/art_rare_concepts.py --sheet         # design/rare_concepts/sheet.jpg (current / A / B)

Raw output: tool/titi_gen/rare/<key>.png (git-ignored). Needs ~/.supabase/ttspot-kie-key.txt
(never commit it). Kie rate-limits bursts (429), so tasks are created ~4 s apart.
"""
import json, os, shutil, sys, time, uuid, urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(ROOT)
OUT = os.path.join(ROOT, 'titi_gen', 'rare')
DST = os.path.join(REPO, 'design', 'rare_concepts')
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


# ---------------------------------------------------------------- prompts

CARDS = {
    'c5': {
        'ref': 'assets/cards/c5.jpg',
        'name': "card 05 'Waiting for the Meet'",
        'no': '05',
        'title': "'WAITING' on the first line in black and 'FOR THE MEET' on the second line in red, with a short red brush swoosh under it",
        'line': 'Good cars. Greater company.',
        'bg': ('a deep, rich warm caramel and toffee brown with a golden-tan glow behind the figure (a richer, deeper version of the '
               'pale beige of the current card), keeping the same faint city skyline, flyover, winding road and checkered-flag motifs '
               'in slightly lighter tones of the same colour'),
        'pose': ('the same sitting pose and happy face (closed smiling eyes, big open smile) as the first reference: he holds the white '
                 'TTSPOT takeaway coffee cup in his hand on the left of the image; the glossy black full-face helmet with the TTSPOT '
                 'logo rests on the base right beside him on the right of the image; the black square sign reading "MEET UP" with a '
                 'white arrow stands on a short black post planted into the base behind the helmet'),
        'props': 'coffee cup, helmet and MEET UP sign',
        'finish': ('the red stripes of the cone are a warm champagne-bronze metallic finish (polished, softly reflective, like brushed '
                   'rose-champagne gold); the white parts are glossy pearl-white vinyl; the reflective bands are mirror-polished '
                   'chrome; the arms, hands and wheel faces are glossy black vinyl; the red trims on the wheels are champagne-bronze too'),
        'sparkle': 'small warm golden-white four-point sparkle glints',
    },
    'c6': {
        'ref': 'assets/cards/c6.jpg',
        'name': "card 06 'Helping on the Road'",
        'no': '06',
        'title': "'HELPING' on the first line in black and 'ON THE ROAD' on the second line in bright emerald green, with a short green brush swoosh under it",
        'line': 'Safer drives. Brighter journeys.',
        'bg': ('a deep, rich emerald and jade green with a soft minty glow behind the figure (a richer, deeper version of the pale '
               'mint of the current card), keeping the same faint globe grid, winding road with dashed lines and checkered-flag '
               'motifs in slightly lighter tones of the same colour'),
        'pose': ('the same sitting pose and face (winking, small smile) as the first reference: a thumbs up with his hand on the left '
                 'of the image and a silver wrench held in his hand on the right of the image; the red-and-black TTSPOT toolbox sits '
                 'on the base beside him on the left of the image and the red warning triangle stands on the base beside him on the '
                 'right of the image'),
        'props': 'wrench, toolbox and warning triangle',
        'finish': ('the red stripes of the cone are an emerald-green pearlescent finish (deep green with a pearly shimmer that shifts '
                   'to teal and soft gold in the highlights); the white parts are glossy pearl-white vinyl; the reflective bands are '
                   'mirror-polished chrome; the arms, hands and wheel faces are glossy black vinyl; the red trims on the wheels are '
                   'emerald pearlescent too'),
        'sparkle': 'small white and pale mint four-point sparkle glints',
    },
}

BASE = ('one round glossy display base: a short, wide black disc plinth with a thin polished silver rim and a soft mirror '
        'reflection on its top surface, just big enough for the figure and its props, no text on the base')


def frame(c):
    return (
        f"Redesign the first reference image, blind-box collectible {c['name']} from the TT Spot 'TiTi' card series, as its RARE-tier "
        f"edition. The second reference image is a common card from the same series: keep the exact same card proportions, layout and "
        f"typography style as the series.\n\n"
        f"LAYOUT (same as the series, portrait 2:3 card): the TTSPOT logo (the red-and-black 'TT' mark with the small checkered corner "
        f"and the 'TTSPOT' wordmark below it) in the top-left corner inside the frame. A big, chunky, rounded, heavy bold title in the "
        f"bottom-left with a thick white sticker outline, exactly like the series titles: {c['title']}. Under the title one short line in "
        f"a clean small sans-serif: '{c['line']}'. The SERIES box in the bottom-right corner: a rounded box with 'SERIES' in small "
        f"capitals and a big bold '{c['no']}' below it.\n\n"
        f"RARE TREATMENT: the card frame (the border around the artwork, plain white on the common cards) is a polished silver "
        f"holographic foil with a soft rainbow iridescent sheen, like a premium trading-card foil border, and the SERIES box has a "
        f"matching silver foil edge. A small silver foil tag reading 'RARE' sits directly above the SERIES box. The background is "
        f"{c['bg']}. A few {c['sparkle']} around the figure, subtle and tasteful, not busy.\n\n"
        f"MUCH LESS SMALL TEXT: remove the 'Malaysia's car community in one place' block, the 'Drive Connect Explore Together' list "
        f"and the handwritten script note. The only text on the whole card is: the TTSPOT logo, the title, the one short line, "
        f"'RARE', 'SERIES {c['no']}', 'DRIVE SAFE' on the sash, and the small TTSPOT logos on the props and wheels"
        + (", and 'MEET UP' on the sign" if c['no'] == '05' else '') + ". All text crisp and correctly spelled.\n\n"
    )


def titi_a(c):
    return (
        f"THE FIGURE: TiTi exactly as in both references: the red-and-white striped traffic-cone mascot with silver reflective "
        f"bands, the same cute face with rosy cheeks, round black arms and hands, the black 'DRIVE SAFE' sash (DRIVE in white, SAFE "
        f"in red) with the little house-and-heart icon, and two big round black wheel feet with the TTSPOT logo; same colours, same "
        f"proportions, same soft flocked plush texture. {c['pose'][0].upper() + c['pose'][1:]}. Present it as a collectible figure "
        f"product shot that could be manufactured: TiTi and his {c['props']} sit together on {BASE}; one clear pose, a clean "
        f"silhouette, every prop held in his hands or standing on the base, nothing floating. Front view from slightly above, the "
        f"same camera angle and size as the series, soft studio lighting with a soft contact shadow and a gentle rim light, the "
        f"figure centred in the upper-middle of the card above the title."
    )


def titi_b(c):
    return (
        f"THE FIGURE: TiTi as a special-finish vinyl collectible figure variant (a rare chase figure, Pop Mart style), glossy "
        f"smooth hard vinyl instead of plush fabric, but unmistakably TiTi: exactly his cone shape, stripe layout, proportions and "
        f"cute face with rosy cheeks, the black 'DRIVE SAFE' sash (DRIVE in white, SAFE in red) with the little house-and-heart "
        f"icon, and two big round wheel feet with the TTSPOT logo. Special finish: {c['finish']}. {c['pose'][0].upper() + c['pose'][1:]}. "
        f"The {c['props']} are sculpted glossy vinyl pieces that belong to the figure. TiTi and his props stand together on {BASE}; "
        f"one clear pose, a clean silhouette, every prop held in his hands or attached to the base, nothing floating. Studio "
        f"product-shot lighting: a soft key light, crisp specular highlights on the metallic and glossy surfaces, a rim light that "
        f"separates the figure from the background, a soft contact shadow. Front view from slightly above, the same camera angle and "
        f"size as the series, the figure centred in the upper-middle of the card above the title."
    )


PROMPTS = {
    'A_c5': frame(CARDS['c5']) + titi_a(CARDS['c5']),
    'A_c6': frame(CARDS['c6']) + titi_a(CARDS['c6']),
    'B_c5': frame(CARDS['c5']) + titi_b(CARDS['c5']),
    'B_c6': frame(CARDS['c6']) + titi_b(CARDS['c6']),
}


# ---------------------------------------------------------------- generation

def run(jobs, force=False):
    tasks = {}
    for k, (prompt, refs, ar) in jobs.items():
        raw = os.path.join(OUT, k + '.png')
        if os.path.exists(raw):
            if not force:
                print('skip (exists)', k, flush=True)
                continue
            n = 1
            while os.path.exists(os.path.join(OUT, f'{k}.v{n}.png')):
                n += 1
            shutil.move(raw, os.path.join(OUT, f'{k}.v{n}.png'))
        inp = {'prompt': prompt, 'input_urls': refs, 'aspect_ratio': ar, 'resolution': '1K'}
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

# Pillow touch-ups on the finished 768x1152 card. A_c6's 'RARE' came out as white
# letters with a thin outline, which vanish at thumbnail size; the other three have
# dark letters. Refill the tag interior from its own left/right edges and redraw it.
# (tag interior box on the card, text box inside it)
RETOUCH_RARE = {'A_c6': ((643, 936, 723, 967), (652, 941, 714, 962))}


def retouch_rare(im, box, text_box):
    from PIL import Image, ImageDraw, ImageFont
    x0, y0, x1, y1 = box
    tx0, ty0, tx1, ty1 = text_box
    px = im.load()
    for y in range(y0, y1):  # per row: linear blend between the letter-free edges
        l = [sum(px[x, y][c] for x in range(x0 + 1, tx0)) / (tx0 - x0 - 1) for c in range(3)]
        r = [sum(px[x, y][c] for x in range(tx1, x1 - 1)) / (x1 - 1 - tx1) for c in range(3)]
        for x in range(tx0 - 2, tx1 + 2):
            t = (x - (tx0 - 2)) / (tx1 - tx0 + 3)
            px[x, y] = tuple(round(l[c] * (1 - t) + r[c] * t) for c in range(3))
    # dark heavy caps, drawn 4x and scaled down for clean anti-aliasing
    s = 4
    w, h = (tx1 - tx0) * s, (ty1 - ty0) * s
    f = ImageFont.truetype('C:/Windows/Fonts/ariblk.ttf', 17 * s)
    layer = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(layer)
    bb = d.textbbox((0, 0), 'RARE', font=f)
    d.text(((w - (bb[2] - bb[0])) / 2 - bb[0], (h - (bb[3] - bb[1])) / 2 - bb[1]), 'RARE', font=f, fill=255)
    mask = layer.resize((tx1 - tx0, ty1 - ty0), Image.LANCZOS)
    im.paste((22, 22, 22), (tx0, ty0, tx1, ty1), mask)
    return im


def install():
    """Fit each raw image to the card size (768x1152, centre-crop if the aspect differs) as a JPG."""
    from PIL import Image
    os.makedirs(DST, exist_ok=True)
    for k in PROMPTS:
        src = os.path.join(OUT, k + '.png')
        if not os.path.exists(src):
            print('missing', k, flush=True)
            continue
        im = Image.open(src).convert('RGB')
        tw, th = CARD
        s = max(tw / im.width, th / im.height)
        im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
        l, t = (im.width - tw) // 2, (im.height - th) // 2
        im = im.crop((l, t, l + tw, t + th))
        if k in RETOUCH_RARE:
            im = retouch_rare(im, *RETOUCH_RARE[k])
        dst = os.path.join(DST, k + '.jpg')
        im.save(dst, quality=90, optimize=True, progressive=True)
        print('installed', os.path.relpath(dst, REPO), im.size, os.path.getsize(dst), 'bytes', flush=True)


def sheet():
    """Comparison sheet: rows current / A / B, columns 05 / 06, labelled."""
    from PIL import Image, ImageDraw, ImageFont
    fonts = 'C:/Windows/Fonts/'

    def font(name, size):
        try:
            return ImageFont.truetype(fonts + name, size)
        except OSError:
            return ImageFont.load_default()

    cw, ch = 420, 630
    pad, gap, left, top = 48, 28, 300, 150
    W = left + 2 * cw + gap + pad
    H = top + 3 * ch + 2 * gap + pad
    bg, ink, sub = (246, 246, 246), (20, 20, 20), (110, 110, 110)
    im = Image.new('RGB', (W, H), bg)
    d = ImageDraw.Draw(im)
    d.text((pad, 44), 'TT Spot blind-box cards: rare-tier concepts', font=font('seguibl.ttf', 40), fill=ink)
    for j, lab in enumerate(['05  Waiting for the Meet', '06  Helping on the Road']):
        d.text((left + j * (cw + gap), top - 46), lab, font=font('segoeuib.ttf', 26), fill=ink)
    rows = [
        ('Current', 'Rare cards look like\nthe commons', {'c5': 'assets/cards/c5.jpg', 'c6': 'assets/cards/c6.jpg'}),
        ('A  Rare frame', 'Silver holo frame,\nRARE tag, deeper colour,\nless text, display base', {'c5': 'design/rare_concepts/A_c5.jpg', 'c6': 'design/rare_concepts/A_c6.jpg'}),
        ('B  Special finish', 'A + TiTi as a\nspecial-finish vinyl\nfigure (bronze / emerald)', {'c5': 'design/rare_concepts/B_c5.jpg', 'c6': 'design/rare_concepts/B_c6.jpg'}),
    ]
    for i, (name, note, srcs) in enumerate(rows):
        y = top + i * (ch + gap)
        d.text((pad, y + 8), name, font=font('seguibl.ttf', 30), fill=ink)
        d.multiline_text((pad, y + 58), note, font=font('segoeui.ttf', 21), fill=sub, spacing=6)
        for j, c in enumerate(['c5', 'c6']):
            x = left + j * (cw + gap)
            card = Image.open(os.path.join(REPO, srcs[c])).convert('RGB').resize((cw, ch), Image.LANCZOS)
            im.paste(card, (x, y))
            d.rectangle((x - 1, y - 1, x + cw, y + ch), outline=(215, 215, 215))
    dst = os.path.join(DST, 'sheet.jpg')
    im.save(dst, quality=88, optimize=True, progressive=True)
    print('sheet', os.path.relpath(dst, REPO), im.size, os.path.getsize(dst), 'bytes', flush=True)


if __name__ == '__main__':
    args = sys.argv[1:]
    if '--install' in args:
        install()
        sys.exit()
    if '--sheet' in args:
        sheet()
        sys.exit()
    if '--print' in args:
        for k, p in PROMPTS.items():
            print(f'== {k} ==\n{p}\n')
        sys.exit()
    force = '--force' in args
    only = {a for a in args if not a.startswith('--')}
    before = credits()
    common = upload(os.path.join(REPO, 'assets/cards/c1.jpg'))
    refs = {c: upload(os.path.join(REPO, v['ref'])) for c, v in CARDS.items()}
    jobs = {k: (p, [refs[k.split('_')[1]], common], '2:3') for k, p in PROMPTS.items()}
    if only:
        jobs = {k: v for k, v in jobs.items() if k in only}
    run(jobs, force)
    after = credits()
    print('Kie credits:', before, '->', after, flush=True)

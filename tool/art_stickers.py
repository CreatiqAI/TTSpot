"""Chat sticker packs: TiTi (the mascot with Manglish car-culture captions) and
Car talk (fun car-culture objects). Kie GPT Image 2 image-to-image for the art
that doesn't exist yet, Pillow for the captions and the die-cut finish.

  python tool/art_stickers.py credits          # Kie balance
  python tool/art_stickers.py gen [key ...]    # renders missing art into build/sticker_art/<key>.png
  python tool/art_stickers.py build            # assets/stickers/<pack>/<key>.webp + design/stickers/sheet.jpg

Needs ~/.supabase/ttspot-kie-key.txt (never commit it). Transparent backgrounds
only work at 1K. Kie answers 429 when tasks come faster than ~4 s apart, and
result downloads can take minutes (600 s timeout).

To redo one render: delete build/sticker_art/<key>.png and run `gen <key>`.
The sticker keys are what chat messages store (messages.sticker), so never
rename a shipped key; add a new one instead. The app's list lives in
lib/features/social/presentation/chat_stickers.dart.
"""
import io, json, math, os, sys, time, urllib.request, uuid

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(ROOT)
RAW = os.path.join(REPO, 'build', 'sticker_art')
OUT = os.path.join(REPO, 'assets', 'stickers')
SHEET = os.path.join(REPO, 'design', 'stickers', 'sheet.jpg')
FONT = os.path.join(REPO, 'assets', 'fonts', 'BarlowCondensed-ExtraBold.ttf')

INK = (16, 16, 16, 255)
RED = (224, 0, 8, 255)
WHITE = (255, 255, 255, 255)

# ---------------------------------------------------------------- the packs ---
# (key, caption, art, caption style, caption place)
#   art: 'titi/<pose>' reuses assets/titi/<pose>.png, 'gen' renders PROMPTS[key]
#   style: 'white' = white fill + dark stroke, 'red' = brand red + white stroke
#   place: 'bottom' or 'top' of the sticker (whichever keeps TiTi's face clear)
TITI = [
    ('titi_yo', 'YO BRO!', 'titi/wave', 'red', 'bottom'),
    ('titi_otw', 'OTW!', 'titi/rolling', 'red', 'top'),
    ('titi_jomtt', 'JOM TT!', 'titi/flag', 'white', 'bottom'),
    ('titi_steady', 'STEADY BOS', 'titi/thumbsup', 'red', 'bottom'),
    ('titi_shiok', 'SHIOK!', 'titi/celebrate', 'white', 'bottom'),
    ('titi_paiseh', 'PAISEH', 'gen', 'red', 'bottom'),
    ('titi_waitme', 'WAIT ME!', 'titi/stop', 'white', 'bottom'),
    ('titi_siap', 'SIAP!', 'gen', 'red', 'bottom'),
    ('titi_mamak', 'MAMAK?', 'gen', 'white', 'bottom'),
    ('titi_niceride', 'NICE RIDE!', 'titi/camera', 'red', 'bottom'),
    ('titi_tido', 'TIDO DULU', 'titi/sleeping', 'white', 'bottom'),
    ('titi_loveit', 'LOVE IT', 'titi/heart', 'red', 'bottom'),
    ('titi_whereyou', 'WHERE YOU?', 'titi/binoculars', 'white', 'bottom'),
    ('titi_letsgo', "LET'S GO!", 'titi/mappin', 'red', 'bottom'),
    ('titi_modtime', 'MOD TIME', 'titi/wrench', 'white', 'bottom'),
    ('titi_hahaha', 'HAHAHA', 'gen', 'red', 'bottom'),
    ('titi_terbaik', 'TERBAIK!', 'titi/trophy', 'white', 'bottom'),
    ('titi_gg', 'GG', 'gen', 'white', 'bottom'),
]
CAR = [
    ('car_vroom', 'VROOM!', 'gen', 'white', 'bottom'),
    ('car_tehtarik', 'TEH TARIK\nSATU!', 'gen', 'red', 'bottom'),
    ('car_fulltank', 'FULL TANK', 'gen', 'white', 'bottom'),
    ('car_drift', 'DRIFT!', 'gen', 'red', 'bottom'),
    ('car_parking', 'PARKING?', 'gen', 'white', 'bottom'),
    ('car_turbo', 'TURBO ON!', 'gen', 'red', 'bottom'),
    ('car_needwash', 'NEED WASH', 'gen', 'white', 'bottom'),
    ('car_slowlah', 'SLOW LAH!', 'gen', 'red', 'bottom'),
    ('car_jam', 'JAM GILA!', 'gen', 'white', 'bottom'),
]
PACKS = {'titi': TITI, 'car': CAR}

# ------------------------------------------------------------------ prompts ---
LOOK = ("TiTi, the plush mascot in the reference images: a red-and-white striped traffic-cone plush with silver reflective bands, a cute face with rosy cheeks, "
        "round black felt mitten hands, a black 'DRIVE SAFE' sash with a small white house icon. Keep his exact look, colours and proportions. "
        "ANATOMY, follow strictly: exactly TWO short stubby legs, sitting, one leg on each side, each leg ends in exactly ONE big round foot seen from the sole; "
        "never duplicate a foot, no extra limbs, exactly two arms. "
        "The sole of the foot on the VIEWER'S LEFT shows the white TT Spot logo (stylised white 'TT' with a small red checkered flag and the small word 'TTSPOT' under it); "
        "the other sole is plain black felt. Detailed soft felt texture, crisp 3D plush render, soft studio light, centred, full body, "
        "transparent background, nothing else in frame, no text other than DRIVE SAFE and the foot logo. Pose: ")

THING = ("A single playful sticker illustration in the glossy, soft, rounded 3D toy style of the reference image: chunky shapes, bright clean colours, "
         "soft studio light, a little exaggerated and fun. Generic and unbranded: no manufacturer logos, no badges, no number plates, "
         "no readable text or letters unless asked. Isolated on a transparent background, centred, whole subject in frame. The subject: ")

PROMPTS = {
    'titi_paiseh': LOOK + 'shy and embarrassed, bright red blushing cheeks, scratching the back of his cone with one mitten, '
                          'an awkward sheepish grin with eyes looking away, one small sweat drop beside his head',
    'titi_siap': LOOK + 'giving a crisp salute, the mitten on his right side raised to his brow, chest out, '
                        'a proud determined smile, ready for duty',
    'titi_mamak': LOOK + 'holding a tall clear glass of frothy teh tarik (caramel-brown pulled milk tea with a thick foam top) in both mittens, '
                         'a little steam rising, happy and inviting, eyebrows raised as if asking',
    'titi_hahaha': LOOK + 'laughing out loud, eyes squeezed shut into happy arcs, mouth wide open, small tears of joy at the corners of his eyes, '
                          'both mittens holding his tummy, leaning back',
    'titi_gg': LOOK + 'holding up a small white surrender flag on a thin stick, tired deadpan face with half-closed eyes and a flat mouth, '
                      'slouching, defeated but funny',
    'car_vroom': THING + 'a chunky polished chrome exhaust tip seen from the back three-quarter view, shooting a big bright orange-and-blue flame burst '
                         'with a few sparks, dynamic and loud',
    'car_tehtarik': THING + 'a tall clear glass of frothy teh tarik (caramel-brown pulled milk tea) with thick foam spilling over the rim, '
                            'a long stream of tea pouring into it from a small steel mug above, a little steam',
    'car_fulltank': THING + 'a cute red petrol pump with a black hose and nozzle, a round fuel gauge on it with the needle at full, '
                            'a happy little face on the pump, a fuel droplet beside it',
    'car_drift': THING + 'one chunky car tyre on a shiny alloy rim, tilted sideways on a small piece of asphalt with black skid marks, '
                         'huge fluffy clouds of white tyre smoke billowing out behind it',
    'car_parking': THING + 'a blue square parking sign with a big white letter P on a short grey pole, the sign tilted, '
                           'a little worried face on the sign, a tiny question-mark shaped puff above it',
    'car_turbo': THING + 'a shiny turbocharger with a polished snail-shaped compressor housing and a heat-blued titanium pipe, '
                         'swirling air streaks being sucked into it, small sparkles',
    'car_needwash': THING + 'a small boxy generic toy city hatchback (like a simple Malaysian kei car: tall boxy body, rectangular headlights, '
                            'a plain slim grille, NOT round headlights, not resembling any real model), front three-quarter view, '
                            'completely covered in brown mud splatter and dust, dirty windows, two tiny buzzing flies above it, no face on the car',
    'car_slowlah': THING + 'a yellow-and-black striped road speed bump, with a small cute chunky generic hatchback bouncing over it, '
                           'all four wheels in the air, motion lines, no face on the car',
    'car_jam': THING + 'three small cute chunky generic cars of different colours stuck bumper to bumper in a short diagonal line, '
                       'red brake lights glowing, a little puff of steam above them, no faces on the cars',
}

# ---------------------------------------------------------------------- Kie ---


def _key():
    return open(os.path.expanduser('~/.supabase/ttspot-kie-key.txt')).read().strip()


def post_json(url, body):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={'Authorization': f'Bearer {_key()}', 'Content-Type': 'application/json'})
    return json.load(urllib.request.urlopen(req, timeout=60))


def get_json(url):
    return json.load(urllib.request.urlopen(urllib.request.Request(url, headers={'Authorization': f'Bearer {_key()}'}), timeout=60))


def upload(local):
    mime = 'image/png' if local.endswith('.png') else 'image/jpeg'
    b = uuid.uuid4().hex
    data = open(local, 'rb').read()
    body = (f'--{b}\r\nContent-Disposition: form-data; name="uploadPath"\r\n\r\nttspot/stickers\r\n--{b}\r\nContent-Disposition: form-data; name="file"; '
            f'filename="{os.path.basename(local)}"\r\nContent-Type: {mime}\r\n\r\n').encode() + data + f'\r\n--{b}--\r\n'.encode()
    req = urllib.request.Request('https://kieai.redpandaai.co/api/file-stream-upload', data=body,
                                 headers={'Authorization': f'Bearer {_key()}', 'Content-Type': f'multipart/form-data; boundary={b}'})
    return json.load(urllib.request.urlopen(req, timeout=120))['data']['downloadUrl']


def credits():
    return get_json('https://api.kie.ai/api/v1/chat/credit').get('data')


def gen(only):
    os.makedirs(RAW, exist_ok=True)
    keys = [k for k in PROMPTS if (not only or k in only) and not os.path.exists(os.path.join(RAW, k + '.png'))]
    if not keys:
        print('nothing to render')
        return
    print('credits before:', credits(), flush=True)
    refs = {}
    if any(k.startswith('titi_') for k in keys):
        refs['titi'] = [upload(os.path.join(REPO, 'assets/cards/c1.jpg')), upload(os.path.join(REPO, 'assets/titi/thumbsup.png'))]
    if any(k.startswith('car_') for k in keys):
        refs['car'] = [upload(os.path.join(REPO, 'assets/kinds/carwash.png'))]
    tasks = {}
    for k in keys:
        inp = {'prompt': PROMPTS[k], 'input_urls': refs[k.split('_')[0]], 'aspect_ratio': '1:1', 'resolution': '1K', 'background': 'transparent'}
        r = {}
        for _ in range(4):
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
                d = get_json(f'https://api.kie.ai/api/v1/jobs/recordInfo?taskId={tasks[k]}').get('data') or {}
            except Exception as e:
                print('poll err', k, e, flush=True)
                continue
            if d.get('state') == 'success':
                url = json.loads(d['resultJson'])['resultUrls'][0]
                for _ in range(3):
                    try:
                        open(os.path.join(RAW, k + '.png'), 'wb').write(urllib.request.urlopen(url, timeout=600).read())
                        break
                    except Exception as e:
                        print('retry download', k, e, flush=True)
                done.add(k)
                print('done', k, flush=True)
            elif d.get('state') == 'fail':
                done.add(k)
                print('FAIL', k, d.get('failMsg'), flush=True)
    print('missing:', [k for k in keys if not os.path.exists(os.path.join(RAW, k + '.png'))], flush=True)
    print('credits after:', credits(), flush=True)

# -------------------------------------------------------------- compositing ---


SIZE = 512
OUTLINE = 10      # die-cut white border, px
SHADOW_BLUR = 6
SHADOW_DY = 4
MARGIN = OUTLINE + SHADOW_BLUR + SHADOW_DY + 2


def trim(im):
    a = im.getchannel('A').point(lambda v: 255 if v > 10 else 0)
    box = a.getbbox()
    return im.crop(box) if box else im


def caption_image(text, style, max_w):
    """The caption as its own RGBA image: thick stroke, slight tilt."""
    fill, stroke = (WHITE, INK) if style == 'white' else (RED, WHITE)
    lines = text.split('\n')
    size = 108 if len(lines) == 1 else 84
    while True:
        font = ImageFont.truetype(FONT, size)
        sw = max(5, size // 11)
        widths = [font.getbbox(l, stroke_width=sw)[2] - font.getbbox(l, stroke_width=sw)[0] for l in lines]
        if max(widths) <= max_w or size <= 40:
            break
        size -= 4
    asc, desc = font.getmetrics()
    line_h = int((asc + desc) * 0.86)
    w = max(widths) + sw * 2 + 8
    h = line_h * len(lines) + sw * 2 + 8
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i, l in enumerate(lines):
        lw = widths[i]
        d.text(((w - lw) / 2 - font.getbbox(l, stroke_width=sw)[0], sw + 4 + i * line_h - int(asc * 0.08)), l, font=font,
               fill=fill, stroke_width=sw, stroke_fill=stroke)
    return trim(img), sw


def compose(art, text, style, place, tilt):
    """Art + caption on a 512 square, inside the die-cut margin."""
    inner = SIZE - 2 * MARGIN
    cap, _ = caption_image(text, style, int(inner * 0.88))
    cap = cap.rotate(tilt, resample=Image.BICUBIC, expand=True)
    cap = trim(cap)
    if cap.width > inner:
        r = inner / cap.width
        cap = cap.resize((int(cap.width * r), int(cap.height * r)), Image.LANCZOS)
    # The caption overlaps the art by ~45% of its height, at the bottom (feet) or the top (cone tip).
    overlap = int(cap.height * 0.4)
    art = trim(art)
    room_h = inner - cap.height + overlap
    s = min(inner / art.width, room_h / art.height)
    art = art.resize((max(1, int(art.width * s)), max(1, int(art.height * s))), Image.LANCZOS)
    total_h = art.height + cap.height - overlap
    top = MARGIN + (inner - total_h) // 2
    canvas = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    ax = (SIZE - art.width) // 2
    cx = (SIZE - cap.width) // 2
    if place == 'top':
        cy = top
        ay = top + cap.height - overlap
    else:
        ay = top
        cy = top + art.height - overlap
    canvas.alpha_composite(art, (ax, ay))
    canvas.alpha_composite(cap, (cx, cy))
    return canvas


def die_cut(img):
    """White die-cut border around everything plus a soft drop shadow."""
    a = img.getchannel('A').point(lambda v: 255 if v > 40 else 0)
    # Round dilation: blur the mask by the border width, then threshold low.
    grown = a.filter(ImageFilter.GaussianBlur(OUTLINE * 0.75)).point(lambda v: 255 if v > 8 else 0)
    grown = grown.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(1.2))
    border = Image.new('RGBA', img.size, WHITE)
    border.putalpha(grown)
    shadow_mask = grown.filter(ImageFilter.GaussianBlur(SHADOW_BLUR)).point(lambda v: int(v * 0.32))
    shifted = Image.new('L', img.size, 0)
    shifted.paste(shadow_mask, (0, SHADOW_DY))
    shadow = Image.new('RGBA', img.size, (0, 0, 0, 255))
    shadow.putalpha(shifted)
    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    out.alpha_composite(shadow)
    out.alpha_composite(border)
    out.alpha_composite(img)
    return out


def save_webp(img, path):
    for q in (82, 76, 70, 62, 55):
        buf = io.BytesIO()
        img.save(buf, 'WEBP', quality=q, method=6, alpha_quality=90)
        if buf.tell() <= 60 * 1024:
            break
    open(path, 'wb').write(buf.getvalue())
    return buf.tell()


def art_for(key, src):
    path = os.path.join(REPO, 'assets', src + '.png') if src.startswith('titi/') else os.path.join(RAW, key + '.png')
    return Image.open(path).convert('RGBA')


def build():
    tiles = []
    for pack, items in PACKS.items():
        os.makedirs(os.path.join(OUT, pack), exist_ok=True)
        for i, (key, text, src, style, place) in enumerate(items):
            try:
                art = art_for(key, src)
            except FileNotFoundError:
                print('MISSING ART', key)
                continue
            tilt = (-6, 5, -4, 6)[i % 4]
            sticker = die_cut(compose(art, text, style, place, tilt))
            n = save_webp(sticker, os.path.join(OUT, pack, key + '.webp'))
            print(f'{pack}/{key}.webp {n // 1024} KB')
            tiles.append((key, sticker))
    # Contact sheet for the owner: every sticker on a light chat background.
    cols, cell = 6, 260
    rows = math.ceil(len(tiles) / cols)
    sheet = Image.new('RGB', (cols * cell, rows * (cell + 26) + 10), (239, 234, 226))
    d = ImageDraw.Draw(sheet)
    label = ImageFont.truetype(FONT, 20)
    for i, (key, st) in enumerate(tiles):
        x, y = (i % cols) * cell, (i // cols) * (cell + 26) + 10
        t = st.resize((cell - 20, cell - 20), Image.LANCZOS)
        sheet.paste(t, (x + 10, y), t)
        d.text((x + cell / 2, y + cell - 12), key, font=label, fill=(90, 90, 90), anchor='mt')
    os.makedirs(os.path.dirname(SHEET), exist_ok=True)
    sheet.save(SHEET, quality=88)
    print('sheet', SHEET, len(tiles), 'stickers')


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'build'
    if cmd == 'credits':
        print(credits())
    elif cmd == 'gen':
        gen(set(sys.argv[2:]))
    elif cmd == 'build':
        build()
    else:
        print(__doc__)

"""TiTi AI chat background: a soft "TiTi's workshop" by day (light) and a "pit garage at night"
(dark), rendered by Kie GPT Image 2 and faded by Pillow so the chat stays readable.

  python tool/art_titi_ai_bg.py credits        # Kie balance
  python tool/art_titi_ai_bg.py gen [key ...]  # renders missing raw art into build/titi_ai_bg/<key>.png
  python tool/art_titi_ai_bg.py build          # assets/wallpapers/titi_ai_<light|dark>.webp
                                               # + design/wallpapers/titi_ai.jpg (preview with mock bubbles)

Keys: light_a, light_b, dark_a, dark_b (two takes per mode; PICK chooses the shipped one).

Needs ~/.supabase/ttspot-kie-key.txt (never commit it). Image-to-image with TiTi's card and a
pose as references, so the little TiTi in the scene is on model. Kie answers 429 when tasks come
faster than ~4 s apart. About 7 credits per 1K image.

The finish (build): the raw render is fitted to a 720x1560 portrait canvas (BoxFit.cover in the
app, pinned to the bottom), pulled towards the app's ground colour (light #FFFFFF-ish warm, dark
#0F1115-ish) so it reads as a whisper behind the bubbles, a soft top fade into plain ground where
the app bar sits, and a little grain so the gradient doesn't band. The app paints bubbles and cards
with a solid or near-solid fill on top (lib/features/titi/presentation/titi_background.dart).

What was made (2026-10-02): the four takes in one pass, no retries, Kie credits 750 -> 726 (24 spent).
Shipped light_a (workshop by day) and dark_a (pit garage at night): the same layout, covered car on the
left, red tool chest, TiTi on a tyre stack bottom right, so light and dark feel like one place.
"""
import json, os, sys, time, urllib.request, uuid

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(ROOT)
RAW = os.path.join(REPO, 'build', 'titi_ai_bg')
OUT = os.path.join(REPO, 'assets', 'wallpapers')
PREVIEW = os.path.join(REPO, 'design', 'wallpapers', 'titi_ai.jpg')
PHOSPHOR = os.path.join(REPO, 'assets', 'fonts', 'Phosphor.ttf')

W, H = 720, 1560          # 6:13 portrait, BoxFit.cover pinned to the bottom of the chat body

# The shipped take per mode (after looking at build/titi_ai_bg/*.png).
PICK = {'light': 'light_a', 'dark': 'dark_a'}

# ------------------------------------------------------------------ prompts ---
TITI = ("TiTi, the small plush mascot in the reference images (a red-and-white striped traffic-cone plush with a cute smiling face, "
        "round black felt mitten hands and a black 'DRIVE SAFE' sash), keep his exact look, ")

COMMON = ("Tall portrait wallpaper for a chat screen, seen straight on, calm and premium, soft 3D clay-like render with gentle global light. "
          "Composition: the upper two thirds are a mostly plain, uncluttered back wall with only a few faint shapes; all the detail sits in "
          "the bottom third. Very low contrast, matte, muted, minimal, soft shadows, slight depth-of-field blur on the background. "
          "Accents only in one red (#E00008), used sparingly. No text, no letters, no numbers, no logos, no people, no watermark. ")

PROMPTS = {
    'light_a': COMMON + (
        "Scene: TiTi's workshop by day, a tidy boutique car-detailing garage with warm off-white walls and a pale concrete floor, "
        "a softly lit pegboard with neatly hung tools, a red rolling tool chest, a stack of two tyres, a couple of small traffic cones, "
        "the rounded silhouette of a sports car under a pale grey car cover on the left, daylight from high windows. "
        "In the lower right, " + TITI + "sitting small on the tyre stack holding a tiny wrench, relaxed and happy. "
        "Palette: cream, warm white, light grey, a little red."),
    'light_b': COMMON + (
        "Scene: a bright minimalist pit garage in soft morning light, white tiled walls, pale epoxy floor with faint reflections, "
        "a slim red stripe along the wall, a neat workbench with a red toolbox, folded racing flags, a small coffee cup and a tablet, "
        "a car lift with a covered car far in the background. "
        "On the workbench, lower right, " + TITI + "sitting small, waving. Palette: white, warm grey, a little red."),
    'dark_a': COMMON + (
        "Scene: a pit garage at night, dim and moody, deep charcoal walls and a polished dark concrete floor with soft reflections, "
        "one thin red neon strip glowing softly along the back wall, a covered sports car silhouette on the left, a red tool chest, "
        "a stack of tyres and two small traffic cones in the lower part, faint warm work-lamp light. "
        "In the lower right, " + TITI + "sitting small on the tyre stack, sleepy and cosy, softly lit by the lamp. "
        "Palette: near-black, charcoal, deep navy shadows, a little red glow."),
    'dark_b': COMMON + (
        "Scene: TiTi's workshop late at night, dark slate walls with a faint pegboard of tools, a workbench under a single warm desk lamp, "
        "a red toolbox, rolled-up blueprints, a small trophy, a covered car in deep shadow behind, one soft red neon line on the wall. "
        "On the workbench, lower right, " + TITI + "sitting small, holding a tiny mug, cosy. Palette: near-black, slate, warm lamp glow, a little red."),
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
    body = (f'--{b}\r\nContent-Disposition: form-data; name="uploadPath"\r\n\r\nttspot/titi_ai_bg\r\n--{b}\r\nContent-Disposition: form-data; name="file"; '
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
    before = credits()
    print('credits before:', before, flush=True)
    refs = [upload(os.path.join(REPO, 'assets/cards/c1.jpg')), upload(os.path.join(REPO, 'assets/titi/thumbsup.png'))]
    tasks = {}
    for k in keys:
        inp = {'prompt': PROMPTS[k], 'input_urls': refs, 'aspect_ratio': '2:3', 'resolution': '1K'}
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
    print('credits after:', credits(), '(before', before, ')', flush=True)

# ------------------------------------------------------------------ finish ---


# Grounds: the colour the art is pulled towards (and the app's fallback colour while it loads).
# Mirrored in TitiBackground (Dart) as the scaffold colour behind the image.
GROUND = {'light': (247, 244, 240), 'dark': (13, 15, 19)}
# How much of the render survives (0 = flat ground, 1 = raw render).
STRENGTH = {'light': 0.28, 'dark': 0.38}


def vfade(w, h, stops):
    """An L mask through [(t, value), ...] top to bottom, smoothstepped."""
    line = Image.new('L', (1, 256))
    for i in range(256):
        t = i / 255
        for (t0, v0), (t1, v1) in zip(stops, stops[1:]):
            if t0 <= t <= t1:
                k = (t - t0) / (t1 - t0) if t1 > t0 else 0
                k = k * k * (3 - 2 * k)
                line.putpixel((0, i), round(v0 + (v1 - v0) * k))
                break
    return line.resize((w, h), Image.BICUBIC)


def cover_bottom(img, w, h):
    """BoxFit.cover pinned to the bottom (the app's Alignment.bottomCenter)."""
    k = max(w / img.width, h / img.height)
    s = img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS)
    x = (s.width - w) // 2
    return s.crop((x, s.height - h, x + w, s.height))


def finish(raw, mode):
    src = Image.open(raw).convert('RGB')
    # The render is 2:3; extend it upward with its own (blurred, stretched) top band so the
    # 6:13 canvas has a calm wall up top instead of cropping the scene's sides away.
    k = W / src.width
    art = src.resize((W, round(src.height * k)), Image.LANCZOS)
    canvas = Image.new('RGB', (W, H), GROUND[mode])
    band = art.crop((0, 0, W, max(8, art.height // 10))).resize((W, H - art.height + 40), Image.BICUBIC).filter(ImageFilter.GaussianBlur(28))
    canvas.paste(band, (0, 0))
    seam = vfade(W, art.height, [(0, 0), (0.12, 255), (1, 255)])
    canvas.paste(art, (0, H - art.height), seam)
    # Soften: a touch of blur and less saturation, so nothing competes with the bubbles.
    canvas = canvas.filter(ImageFilter.GaussianBlur(1.2))
    canvas = ImageEnhance.Color(canvas).enhance(0.85 if mode == 'light' else 0.9)
    # Pull towards the ground colour.
    ground = Image.new('RGB', (W, H), GROUND[mode])
    out = Image.blend(ground, canvas, STRENGTH[mode])
    # Calm the top (app bar + first bubbles): fade to plain ground over the top 30 %.
    top = vfade(W, H, [(0, 255), (0.08, 230), (0.34, 0), (1, 0)])
    out = Image.composite(ground, out, top)
    # A whisper of grain against banding.
    noise = Image.effect_noise((W, H), 8).point(lambda v: 128 + (v - 128) // 3)
    out = ImageChops.add(out, Image.merge('RGB', (noise, noise, noise)), 1, -128)
    return out


# -------------------------------------------------------------- the preview ---
FONT_DIR = 'C:/Windows/Fonts'


def font(size, bold=False):
    for name in (('segoeuib.ttf', 'arialbd.ttf') if bold else ('segoeui.ttf', 'arial.ttf')):
        p = os.path.join(FONT_DIR, name)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


# Mirrors TitiBackground's bubble colours (Dart). Member = right, TiTi = left.
MOCK = {
    'light': dict(bg=(255, 255, 255), text=(0, 0, 0), sub=(115, 115, 115), border=(219, 219, 219),
                  mine=(225, 228, 234), theirs=(255, 255, 255, 240), card=(255, 255, 255, 245), chip=(255, 255, 255, 230)),
    'dark': dict(bg=(15, 17, 21), text=(242, 243, 245), sub=(154, 160, 168), border=(46, 51, 60),
                 mine=(35, 39, 47), theirs=(22, 25, 32, 240), card=(22, 25, 32, 245), chip=(22, 25, 32, 230)),
}


def mock(mode, wall, w=760, h=1500):
    c = MOCK[mode]
    im = Image.new('RGBA', (w, h), c['bg'] + (255,))
    bar, comp = 120, 130
    body_h = h - bar - comp
    im.paste(cover_bottom(wall, w, body_h), (0, bar))
    d = ImageDraw.Draw(im)
    d.text((24, 36), chr(0xe058), font=ImageFont.truetype(PHOSPHOR, 44), fill=c['text'])
    titi = Image.open(os.path.join(REPO, 'assets/titi/wave.png')).convert('RGBA').resize((70, 70), Image.LANCZOS)
    im.alpha_composite(titi, (88, 25))
    d.text((172, 26), 'TiTi', font=font(32, bold=True), fill=c['text'])
    d.text((172, 66), 'Your TT Spot assistant', font=font(23), fill=c['sub'])
    d.line((0, bar - 1, w, bar - 1), fill=c['border'], width=1)

    layer = Image.new('RGBA', im.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    y = bar + 60

    def bubble(text, mine, y):
        f = font(29)
        lines = text.split('\n')
        tw = max(ld.textlength(t, font=f) for t in lines)
        bw, bh = tw + 56, 40 * len(lines) + 34
        x = w - 24 - bw if mine else 24
        fill = c['mine'] if mine else c['theirs']
        ld.rounded_rectangle((x, y, x + bw, y + bh), 34, fill=fill, outline=None if mine else c['border'], width=0 if mine else 2)
        for i, t in enumerate(lines):
            ld.text((x + 28, y + 15 + i * 40), t, font=f, fill=c['text'])
        return y + bh + 18

    y = bubble('Meets this weekend near me', True, y)
    y = bubble('Two this weekend near TTDI:\nSat 9 pm, Myvi night at Bangsar\nSun 7 am, coffee run, Genting', False, y)
    # An action card.
    ld.rounded_rectangle((24, y, w - 140, y + 170), 28, fill=c['card'], outline=c['border'], width=2)
    ld.rounded_rectangle((48, y + 24, 168, y + 144), 20, fill=(224, 0, 8))
    ld.text((196, y + 34), 'Myvi night, Bangsar', font=font(30, bold=True), fill=c['text'])
    ld.text((196, y + 82), 'Sat 9:00 pm  ·  32 going', font=font(25), fill=c['sub'])
    y += 190
    y = bubble('Join the Saturday one', True, y)
    y = bubble("Done, you're in! See you there.", False, y)
    # Typing indicator.
    ld.rounded_rectangle((24, y, 140, y + 64), 32, fill=c['theirs'], outline=c['border'], width=2)
    for i in range(3):
        cx = 56 + i * 26
        ld.ellipse((cx - 7, y + 25, cx + 7, y + 39), fill=c['sub'])
    im.alpha_composite(layer)
    d = ImageDraw.Draw(im)
    top = h - comp
    d.rectangle((0, top, w, h), fill=c['bg'])
    d.line((0, top, w, top), fill=c['border'], width=1)
    d.rounded_rectangle((24, top + 24, w - 120, top + 106), 41, fill=c['bg'], outline=c['border'], width=2)
    d.text((56, top + 46), 'Ask TiTi anything', font=font(29), fill=c['sub'])
    d.ellipse((w - 104, top + 24, w - 22, top + 106), fill=(224, 0, 8))
    return im.convert('RGB')


def build():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    walls = {}
    for mode, key in PICK.items():
        raw = os.path.join(RAW, key + '.png')
        walls[mode] = finish(raw, mode)
        path = os.path.join(OUT, f'titi_ai_{mode}.webp')
        q = 88
        while True:
            walls[mode].save(path, 'WEBP', quality=q, method=6)
            kb = os.path.getsize(path) / 1024
            if kb <= 200 or q <= 50:
                break
            q -= 6
        print(f'  {os.path.relpath(path, REPO)}  {W}x{H}  q{q}  {kb:.0f} KB')
        assert kb <= 200, f'{path} is {kb:.0f} KB'
    # Preview: raw takes on top, finished light + dark mocks below.
    pw, ph = 456, 900
    gap, top = 36, 140
    takes = [k for k in PROMPTS if os.path.exists(os.path.join(RAW, k + '.png'))]
    tw = 240
    th = 360
    width = max(gap + 2 * (pw + gap), gap + len(takes) * (tw + gap))
    height = top + th + 70 + ph + 90
    sheet = Image.new('RGB', (width, height), (236, 233, 228))
    d = ImageDraw.Draw(sheet)
    d.text((gap, 30), 'TiTi AI chat background', font=font(44, bold=True), fill=(16, 16, 16))
    d.text((gap, 88), f'Raw takes (shipped: {PICK["light"]}, {PICK["dark"]}), then the finished light and dark chat.', font=font(24), fill=(90, 90, 90))
    for i, k in enumerate(takes):
        t = Image.open(os.path.join(RAW, k + '.png')).convert('RGB')
        t = t.resize((tw, round(t.height * tw / t.width)), Image.LANCZOS).crop((0, 0, tw, th))
        x = gap + i * (tw + gap)
        sheet.paste(t, (x, top))
        d.text((x, top + th + 10), k + ('  (shipped)' if k in PICK.values() else ''), font=font(22, bold=True), fill=(16, 16, 16))
    y = top + th + 70
    for i, mode in enumerate(('light', 'dark')):
        m = mock(mode, walls[mode]).resize((pw, ph), Image.LANCZOS)
        x = gap + i * (pw + gap)
        frame = Image.new('L', (pw, ph), 0)
        ImageDraw.Draw(frame).rounded_rectangle((0, 0, pw - 1, ph - 1), 36, fill=255)
        sheet.paste(m, (x, y), frame)
        d.rounded_rectangle((x - 1, y - 1, x + pw, y + ph), 36, outline=(190, 186, 180), width=2)
        d.text((x + 4, y + ph + 14), f'TiTi AI  ·  {mode}', font=font(28, bold=True), fill=(16, 16, 16))
    sheet.save(PREVIEW, quality=86)
    print('  ' + os.path.relpath(PREVIEW, REPO))


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'build'
    if cmd == 'credits':
        print(credits())
    elif cmd == 'gen':
        gen(sys.argv[2:])
    elif cmd == 'build':
        build()
    else:
        print(__doc__)

"""Sample art for the AI portrait picker: one Porsche 911 painted in all 8 styles,
so members see what they get before they spend points.

  python tool/art_portrait_samples.py credits              # Kie balance
  python tool/art_portrait_samples.py base                 # text-to-image base photo -> build/portrait_samples/base_v<N>.png
  python tool/art_portrait_samples.py styles [id ...]      # each style, image-to-image from the picked base -> <id>_v<N>.png
  python tool/art_portrait_samples.py pick <name> <N>      # choose which take of base / a style ships
  python tool/art_portrait_samples.py build                # assets/portrait_samples/<id>.webp + design/portrait_samples/sheet.jpg

Needs ~/.supabase/ttspot-kie-key.txt (never commit it). Kie answers 429 when
tasks come faster than ~4 s apart, and result downloads can take minutes (600 s
timeout). Raw takes live in build/portrait_samples/ (gitignored); picks.json
there says which take of each ships (default: the newest).

Honesty rule: STYLES and build_prompt() below are copied word for word from
supabase/functions/car-portrait/index.ts, and the request uses the same model,
aspect ratio and resolution, so a sample is what a member would get from a
good phone photo of their car. If the function's prompts change, copy them
here and re-run `styles` + `build`. The only input that differs is the photo
itself (here one generated base photo instead of the member's up-to-3 photos).

Prompt notes (2026-10-01 run): none of the 8 function prompts needed a tweak;
they are used verbatim. Shipped takes: base v1 of 2 (both were good, v1 is
crisper); every style's first take except pastel_dream, whose v1 was a flat
pasted-in look, so it got one retry (v2: soft sky and lake). Cost: 6 Kie
credits per 1K image, 66 credits in all (834 -> 768).
"""
import json, os, sys, time, urllib.request, uuid

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(ROOT)
RAW = os.path.join(REPO, 'build', 'portrait_samples')
OUT = os.path.join(REPO, 'assets', 'portrait_samples')
SHEET = os.path.join(REPO, 'design', 'portrait_samples', 'sheet.jpg')
FONT = os.path.join(REPO, 'assets', 'fonts', 'BarlowCondensed-ExtraBold.ttf')
FONT_SEMI = os.path.join(REPO, 'assets', 'fonts', 'BarlowCondensed-SemiBold.ttf')

# ------------------------------------------------- the edge function, copied ---
# supabase/functions/car-portrait/index.ts: MODEL, ASPECT, RESOLUTION, STYLES, buildPrompt.
MODEL = 'gpt-image-2-image-to-image'
ASPECT = '4:3'
RESOLUTION = '1K'

STYLES = {
    'showroom': "a premium automotive studio shot: seamless dark grey backdrop, soft overhead softbox reflections along the body lines, glossy reflective floor, three-quarter front view, crisp commercial photography, no props",
    'night_city': "a cinematic night scene on a wet Kuala Lumpur street after rain: neon signs and city lights reflecting off the wet road and the paint, shallow depth of field, moody blue and magenta tones, low three-quarter angle",
    'golden_hour': "a warm golden-hour photograph on an empty coastal road: low sun behind the car creating soft rim light and long shadows, warm orange and amber tones, light haze, calm sea and palm trees far in the background",
    'race_poster': "a bold motorsport poster illustration: dynamic low angle, strong motion streaks and speed lines behind the car, dramatic high-contrast lighting, punchy saturated colours, graphic halftone shading, poster composition with clean empty space around the car",
    'pastel_dream': "a dreamy minimal art-print style: soft pastel colour palette (peach, mint, lavender), flat pastel sky, gentle diffused light, very clean minimal background, slightly stylised but the car stays true to life",
    'film': "an analogue 35mm film photograph from the 1990s: visible fine grain, slightly faded colours with lifted blacks, warm Kodak-like tones, natural daylight, a quiet suburban street, light vignette, nostalgic",
    'track_day': "an action panning photograph on a race circuit like Sepang: the car sharp with motion blur on the tarmac and the background, kerbs and grandstand blurred behind, overcast bright daylight, wheels showing rotation blur, sense of speed",
    'line_art': "a clean technical line drawing: fine black ink lines on a plain white background, no colour fill except very light grey shading, blueprint-like precision, side-front three-quarter view, every body line and panel gap drawn accurately",
}
NAMES = {
    'showroom': 'Showroom', 'night_city': 'Night city', 'golden_hour': 'Golden hour', 'race_poster': 'Race poster',
    'pastel_dream': 'Pastel dream', 'film': '35mm film', 'track_day': 'Track day', 'line_art': 'Line art',
}

# The car row the function would see for a member's 911 (year, make, model).
CAR = {'year': 2021, 'make': 'Porsche', 'model': '911 Carrera'}


def build_prompt(car, look):
    bits = ' '.join(str(b) for b in [car.get('year') or '', car['make'], car['model']] if b)
    return ' '.join([
        f'Recreate this exact car, a {bits}, as {look}.',
        'Keep the exact paint colour and finish of the car in the reference photo (do not recolour it), and the same body shape, proportions, wheels, trim, badges and every visible detail; do not change the model or restyle the car.',
        'Remove the number plate or leave it blank. No people, no text, no logos or watermarks added.',
        'Single car, centred, whole car in frame, 1K output.',
    ])


# ------------------------------------------------------------ the base photo ---
# Stands in for a member's own phone photo: ordinary daylight, a Malaysian condo
# car park, nothing staged, so the styles do the work.
BASE_PROMPT = (
    "A realistic, ordinary smartphone photo of a Guards Red Porsche 911 Carrera, current 992 generation (2021), "
    "seen from a three-quarter front view at standing eye height, the whole car in frame with a little space around it. "
    "It is parked in the open-air top deck of a condominium car park in Kuala Lumpur, Malaysia: grey concrete floor with faded white bay lines, "
    "a low concrete parapet, a couple of residential condo towers and tropical trees in the background, a bright hazy tropical sky, "
    "ordinary flat daylight, natural colours, no dramatic lighting. "
    "Stock 992 Carrera details: round LED headlights with four-point daytime running lights, the clean front bumper with three intakes, "
    "five-spoke silver alloy wheels, black side mirrors. "
    "The front number plate is a plain blank black plate with no characters at all. "
    "No people, no other cars in focus, no signage, no text, no other brand logos anywhere."
)


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
    body = (f'--{b}\r\nContent-Disposition: form-data; name="uploadPath"\r\n\r\nttspot/portrait_samples\r\n--{b}\r\nContent-Disposition: form-data; name="file"; '
            f'filename="{os.path.basename(local)}"\r\nContent-Type: {mime}\r\n\r\n').encode() + data + f'\r\n--{b}--\r\n'.encode()
    req = urllib.request.Request('https://kieai.redpandaai.co/api/file-stream-upload', data=body,
                                 headers={'Authorization': f'Bearer {_key()}', 'Content-Type': f'multipart/form-data; boundary={b}'})
    return json.load(urllib.request.urlopen(req, timeout=120))['data']['downloadUrl']


def credits():
    return get_json('https://api.kie.ai/api/v1/chat/credit').get('data')


def create(model, inp):
    r = {}
    for _ in range(4):
        try:
            r = post_json('https://api.kie.ai/api/v1/jobs/createTask', {'model': model, 'input': inp})
        except Exception as e:
            r = {'code': 'ERR', 'msg': str(e)}
        if r.get('code') == 200:
            break
        time.sleep(15)
    time.sleep(4)  # Kie rate limit
    return (r.get('data') or {}).get('taskId'), r


def wait(tasks):
    """tasks: {out_path: task_id}. Polls until each is done, saves the image."""
    done = set()
    for _ in range(150):
        pending = [p for p, t in tasks.items() if t and p not in done]
        if not pending:
            break
        time.sleep(12)
        for p in pending:
            try:
                d = get_json(f'https://api.kie.ai/api/v1/jobs/recordInfo?taskId={tasks[p]}').get('data') or {}
            except Exception as e:
                print('poll err', os.path.basename(p), e, flush=True)
                continue
            if d.get('state') == 'success':
                url = json.loads(d['resultJson'])['resultUrls'][0]
                for _ in range(3):
                    try:
                        open(p, 'wb').write(urllib.request.urlopen(url, timeout=600).read())
                        break
                    except Exception as e:
                        print('retry download', os.path.basename(p), e, flush=True)
                done.add(p)
                print('done', os.path.basename(p), flush=True)
            elif d.get('state') == 'fail':
                done.add(p)
                print('FAIL', os.path.basename(p), d.get('failMsg'), flush=True)


def next_take(name):
    n = 1
    while os.path.exists(os.path.join(RAW, f'{name}_v{n}.png')):
        n += 1
    return os.path.join(RAW, f'{name}_v{n}.png')


def picks():
    path = os.path.join(RAW, 'picks.json')
    return json.load(open(path)) if os.path.exists(path) else {}


def chosen(name):
    """The take that ships: picks.json, else the newest one."""
    n = picks().get(name)
    if n:
        return os.path.join(RAW, f'{name}_v{n}.png')
    takes = sorted((f for f in os.listdir(RAW) if f.startswith(name + '_v') and f.endswith('.png')), key=lambda f: int(f[len(name) + 2:-4]))
    return os.path.join(RAW, takes[-1]) if takes else None


def gen_base(count=1):
    os.makedirs(RAW, exist_ok=True)
    print('credits before:', credits(), flush=True)
    tasks = {}
    for _ in range(count):
        out = next_take('base')
        open(out, 'wb').close()  # reserve the name
        tid, r = create('gpt-image-2-text-to-image', {'prompt': BASE_PROMPT, 'aspect_ratio': ASPECT, 'resolution': RESOLUTION})
        print('task base', os.path.basename(out), r.get('code'), r.get('msg'), flush=True)
        tasks[out] = tid
    wait(tasks)
    print('credits after:', credits(), flush=True)


def gen_styles(only):
    os.makedirs(RAW, exist_ok=True)
    base = chosen('base')
    if not base or not os.path.getsize(base):
        sys.exit('make and pick a base first')
    ids = [s for s in STYLES if not only or s in only]
    print('credits before:', credits(), 'base:', os.path.basename(base), flush=True)
    ref = upload(base)
    tasks = {}
    for s in ids:
        out = next_take(s)
        open(out, 'wb').close()
        tid, r = create(MODEL, {'prompt': build_prompt(CAR, STYLES[s]), 'input_urls': [ref], 'aspect_ratio': ASPECT, 'resolution': RESOLUTION})
        print('task', os.path.basename(out), r.get('code'), r.get('msg'), flush=True)
        tasks[out] = tid
    wait(tasks)
    for p in tasks:
        if os.path.exists(p) and not os.path.getsize(p):
            os.remove(p)
    print('credits after:', credits(), flush=True)


def pick(name, n):
    p = picks()
    p[name] = int(n)
    json.dump(p, open(os.path.join(RAW, 'picks.json'), 'w'), indent=1)


def save_webp(src, dst, width=1024, budget=180 * 1024):
    im = Image.open(src).convert('RGB')
    if im.width != width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    for q in (84, 80, 76, 72, 68, 64, 60):
        im.save(dst, 'WEBP', quality=q, method=6)
        if os.path.getsize(dst) <= budget:
            break
    return os.path.getsize(dst), q


def build():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.dirname(SHEET), exist_ok=True)
    names = ['base'] + list(STYLES)
    srcs = {}
    for n in names:
        src = chosen(n)
        if not src or not os.path.getsize(src):
            sys.exit(f'missing {n}')
        srcs[n] = src
        size, q = save_webp(src, os.path.join(OUT, n + '.webp'))
        print(f'{n}.webp  {size // 1024} KB  q{q}  from {os.path.basename(src)}')
    # Contact sheet: 3 x 3, base first, labelled.
    cw, ch, pad, label = 600, 450, 24, 56
    sheet = Image.new('RGB', (pad + 3 * (cw + pad), 110 + 3 * (ch + label + pad)), (16, 16, 16))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 28), 'TT SPOT  ·  AI PORTRAIT SAMPLES  ·  PORSCHE 911 (992)', font=ImageFont.truetype(FONT, 46), fill=(255, 255, 255))
    f = ImageFont.truetype(FONT_SEMI, 34)
    for i, n in enumerate(names):
        x = pad + (i % 3) * (cw + pad)
        y = 110 + (i // 3) * (ch + label + pad)
        im = Image.open(srcs[n]).convert('RGB')
        im = im.resize((cw, round(im.height * cw / im.width)), Image.LANCZOS)
        if im.height != ch:  # centre-crop to 4:3
            top = max(0, (im.height - ch) // 2)
            im = im.crop((0, top, cw, top + ch))
        sheet.paste(im, (x, y))
        d.text((x, y + ch + 10), 'Base photo (input)' if n == 'base' else NAMES[n], font=f, fill=(224, 0, 8) if n == 'base' else (255, 255, 255))
    sheet.save(SHEET, 'JPEG', quality=86)
    print('sheet', SHEET)


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else ''
    if cmd == 'credits':
        print(credits())
    elif cmd == 'base':
        gen_base(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
    elif cmd == 'styles':
        gen_styles(sys.argv[2:])
    elif cmd == 'pick':
        pick(sys.argv[2], sys.argv[3])
    elif cmd == 'build':
        build()
    else:
        print(__doc__)

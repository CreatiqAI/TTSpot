"""Art batch 4: our own 3D icons for the six event types and for vouchers, in the
same glossy style as assets/kinds (batch 3). Kie GPT Image 2 image-to-image.

  python tool/art_batch4.py                  # generate every missing raw image
  python tool/art_batch4.py meet convoy      # just some keys
  python tool/art_batch4.py --force meet     # regenerate (old raw kept as <key>.old.png)
  python tool/art_batch4.py voucher_used     # needs the raw voucher.png first (used as reference)
  python tool/art_batch4.py --install        # trim, square to 256 px, save into assets/

Raw output: tool/titi_gen/batch4/<key>.png (git-ignored). Installed:
assets/event_types/<event_type db value>.png and assets/vouchers/<key>.png.
Needs ~/.supabase/ttspot-kie-key.txt (never commit it). Kie rate-limits bursts
(429), so tasks are created ~4 s apart.
"""
import json, os, shutil, sys, time, uuid, urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(ROOT)
OUT = os.path.join(ROOT, 'titi_gen', 'batch4')
os.makedirs(OUT, exist_ok=True)
SIZE = 256  # same as assets/kinds
FIT = 250   # the object's longer side inside the 256 px square


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


# Same prefix as batch 3's ICONS so the set matches assets/kinds, plus a nudge
# towards bold, simple shapes that still read at 24 px.
ICON = ('A single glossy 3D app icon object in a soft, rounded, playful 3D style like the reference emoji art, bright clean colours, '
        'soft studio light, isolated on a transparent background, centred, no text, no letters, no numbers, no logos. '
        'Bold, simple, chunky shapes with few parts so it stays readable as a tiny 24 px icon. The object: ')

# Keys are the Postgres event_type values (EventType.db).
EVENT_TYPES = {
    # v2: v1 (three cars side by side) was a wide strip that got tiny at 24 px.
    'meet': 'three small chunky cartoon cars (one red, one white, one dark grey) huddled together on a small round grey asphalt disc, '
            'seen from a high three-quarter angle: two cars in front angled towards each other and one behind them in the middle, '
            'as if gathered at a car meet, with a small red map-pin marker floating above; a compact, roughly square composition',
    'tt': 'a white ceramic coffee cup on a saucer with light steam rising, and a black car key fob on a small silver key ring '
          'resting against the saucer, a relaxed café hangout feel',
    'convoy': 'three small chunky cartoon cars (red in front, then white, then dark grey) driving one behind another along a short '
              'grey S-shaped winding road ribbon with white dashed centre lines, seen from above at an angle, no hill, no trees',
    'trackday': 'a glossy red full-face racing helmet with a dark tinted visor, three-quarter view, with a small black-and-white '
                'chequered racing flag on a short pole crossed behind it',
    'charity': 'a glossy red heart resting in an open, gently cupped cartoon hand in the yellow emoji skin tone, '
               'with a tiny white cartoon car sitting on top of the heart',
    'official': 'a shiny polished gold trophy cup with two handles on a short black base, a small raised red star on the front of the cup',
}

VOUCHERS = {
    'voucher': 'a glossy red coupon ticket with a semicircle notch cut into the middle of each short side, a white dashed tear '
               'line across it near one end, and a single raised white percent sign on the larger part, slightly tilted, slightly curled',
}

# Made from the finished voucher as the reference, so it is the same coupon.
# v2: v1 dropped the percent sign and tore beside the dashes.
USED = ('The exact same coupon ticket as the reference image, same shape, same angle, same raised white percent sign and same 3D style, '
        'but used up: the small end is torn off exactly along the white dashed line (the dashes become the ragged torn edge) and '
        'sits slightly apart from the main piece, which still shows the raised percent sign. The whole thing is desaturated to '
        'soft light grey with the percent sign in white. Isolated on a transparent background, centred, no other text, no letters, no stamp.')


def run(jobs, force=False):
    tasks = {}
    for k, (prompt, refs, bg, ar) in jobs.items():
        raw = os.path.join(OUT, k + '.png')
        if os.path.exists(raw):
            if not force:
                print('skip (exists)', k, flush=True)
                continue
            shutil.move(raw, os.path.join(OUT, k + '.old.png'))
        inp = {'prompt': prompt, 'input_urls': refs, 'aspect_ratio': ar, 'resolution': '1K'}
        if bg:
            inp['background'] = bg
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


def square(src, dst):
    """Trim to the visible pixels, fit the longer side to FIT px and centre it
    on a transparent SIZE px square (as assets/kinds), then save compressed."""
    from PIL import Image
    im = Image.open(src).convert('RGBA')
    a = im.getchannel('A').point(lambda v: 0 if v < 10 else v)  # drop the faint halo
    im.putalpha(a)
    im = im.crop(a.point(lambda v: 255 if v else 0).getbbox())
    k = FIT / max(im.size)
    im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
    out = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    out.alpha_composite(im, ((SIZE - im.width) // 2, (SIZE - im.height) // 2))
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    out.save(dst, optimize=True)
    print('installed', os.path.relpath(dst, REPO), os.path.getsize(dst), 'bytes', flush=True)


def install():
    for k in EVENT_TYPES:
        square(os.path.join(OUT, k + '.png'), os.path.join(REPO, 'assets', 'event_types', k + '.png'))
    for k in list(VOUCHERS) + ['voucher_used']:
        src = os.path.join(OUT, k + '.png')
        if os.path.exists(src):
            square(src, os.path.join(REPO, 'assets', 'vouchers', k + '.png'))


if __name__ == '__main__':
    args = sys.argv[1:]
    if '--install' in args:
        install()
        sys.exit()
    force = '--force' in args
    only = {a for a in args if not a.startswith('--')}
    before = credits()
    fluent = upload(os.path.join(REPO, 'assets/art/coffee.png'))
    jobs = {}
    for k, p in {**EVENT_TYPES, **VOUCHERS}.items():
        jobs[k] = (ICON + p, [fluent], 'transparent', '1:1')
    if 'voucher_used' in only and os.path.exists(os.path.join(OUT, 'voucher.png')):
        jobs['voucher_used'] = (USED, [upload(os.path.join(OUT, 'voucher.png'))], 'transparent', '1:1')
    if only:
        jobs = {k: v for k, v in jobs.items() if k in only}
    run(jobs, force)
    after = credits()
    print('Kie credits:', before, '->', after, flush=True)

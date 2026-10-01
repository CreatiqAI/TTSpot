"""Garage icon for the profile's My garage pill, the twin of the points coin
(assets/prizes/coin.png): same glossy 3D render, transparent background.

  python tool/art_garage_icon.py gen     # render the variants (Kie GPT Image 2)
  python tool/art_garage_icon.py build   # trim + save the picked one

Needs ~/.supabase/ttspot-kie-key.txt (never commit it). Raw renders go to
build/garage_icon/ (gitignored)."""
import json, os, sys, time, urllib.request
sys.path.insert(0, os.path.dirname(__file__))
from art_stickers import post_json, get_json, upload, credits  # noqa: E402
from PIL import Image  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(REPO, 'build', 'garage_icon')
STYLE = ('Match the reference coin icon exactly in rendering style: the same glossy, soft 3D clay-like render, the same '
         'warm studio lighting from the top left, soft inner shading, subtle rim highlight, saturated colours, the same '
         'size in frame and the same three-quarter tilt. Centred, isolated on a transparent background, nothing else in '
         'frame, no text, no letters, no logos. ')
PROMPTS = {
    'medallion': STYLE + 'The subject: a round medallion with the same shape, thickness and bevel as the reference coin, but '
                 'in deep royal-blue enamel with a polished silver rim, and on its face a raised white emblem of a small '
                 'garage: a peaked roof over a roller shutter door with horizontal slats.',
    'house': STYLE + 'The subject: a small chunky toy-like car garage building, white walls, a slate-blue roof, and a '
             'red-and-white roller shutter door half open showing the glossy red front of a small hatchback car inside.',
    'door': STYLE + 'The subject: a rounded-square badge in deep royal blue with a polished silver bevel, holding a small '
            'red-and-white striped roller shutter garage door that is half raised, with a warm light glowing underneath it.',
}


def gen():
    os.makedirs(RAW, exist_ok=True)
    print('credits before:', credits(), flush=True)
    ref = [upload(os.path.join(REPO, 'assets/prizes/coin.png'))]
    tasks = {}
    for k, p in PROMPTS.items():
        if os.path.exists(os.path.join(RAW, k + '.png')):
            continue
        r = post_json('https://api.kie.ai/api/v1/jobs/createTask', {'model': 'gpt-image-2-image-to-image', 'input': {'prompt': p, 'input_urls': ref, 'aspect_ratio': '1:1', 'resolution': '1K', 'background': 'transparent'}})
        tasks[k] = (r.get('data') or {}).get('taskId')
        print('task', k, r.get('code'), r.get('msg'), flush=True)
        time.sleep(4)
    done = set()
    for _ in range(100):
        pending = [k for k, t in tasks.items() if t and k not in done]
        if not pending:
            break
        time.sleep(12)
        for k in pending:
            d = get_json(f'https://api.kie.ai/api/v1/jobs/recordInfo?taskId={tasks[k]}').get('data') or {}
            if d.get('state') == 'success':
                url = json.loads(d['resultJson'])['resultUrls'][0]
                open(os.path.join(RAW, k + '.png'), 'wb').write(urllib.request.urlopen(url, timeout=600).read())
                done.add(k)
                print('done', k, flush=True)
            elif d.get('state') == 'fail':
                done.add(k)
                print('FAIL', k, d.get('failMsg'), flush=True)
    print('credits after:', credits(), flush=True)


def build(pick):
    im = Image.open(os.path.join(RAW, pick + '.png')).convert('RGBA')
    box = im.getchannel('A').point(lambda a: 255 if a > 8 else 0).getbbox()
    im = im.crop(box)
    side = max(im.size)
    sq = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    sq.alpha_composite(im, ((side - im.width) // 2, (side - im.height) // 2))
    # Same canvas as the coin: 128 px for the pill, 256 for crisp 2x/3x screens.
    sq.resize((256, 256), Image.LANCZOS).save(os.path.join(REPO, 'assets/prizes/garage.png'), optimize=True)
    print('saved assets/prizes/garage.png from', pick)


if __name__ == '__main__':
    if sys.argv[1] == 'gen':
        gen()
    else:
        build(sys.argv[2])

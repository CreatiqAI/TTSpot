"""Art batch 3 (not TiTi): car placeholders by body type, enamel badges, spot and
partner category icons, club crests, partner category covers, prize
placeholders and the points coin. Kie GPT Image 2 image-to-image.

  python tool/art_batch3.py            # everything
  python tool/art_batch3.py car_suv    # just some keys

Output: tool/titi_gen/batch3/<key>.png. Needs ~/.supabase/ttspot-kie-key.txt.
Kie rate-limits bursts (429), so tasks are created ~4 s apart.
"""
import json, os, sys, time, uuid, urllib.request

KIE = open(os.path.expanduser('~/.supabase/ttspot-kie-key.txt')).read().strip()
ROOT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(ROOT)
OUT = os.path.join(ROOT, 'titi_gen', 'batch3')
os.makedirs(OUT, exist_ok=True)


def post_json(url, body):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={'Authorization': f'Bearer {KIE}', 'Content-Type': 'application/json'})
    return json.load(urllib.request.urlopen(req, timeout=60))


def get_json(url):
    return json.load(urllib.request.urlopen(urllib.request.Request(url, headers={'Authorization': f'Bearer {KIE}'}), timeout=60))


def upload(local):
    mime = 'image/png' if local.endswith('.png') else 'image/jpeg'
    b = uuid.uuid4().hex
    data = open(local, 'rb').read()
    body = (f'--{b}\r\nContent-Disposition: form-data; name="uploadPath"\r\n\r\nttspot/art\r\n--{b}\r\nContent-Disposition: form-data; name="file"; filename="{os.path.basename(local)}"\r\nContent-Type: {mime}\r\n\r\n').encode() + data + f'\r\n--{b}--\r\n'.encode()
    req = urllib.request.Request('https://kieai.redpandaai.co/api/file-stream-upload', data=body, headers={'Authorization': f'Bearer {KIE}', 'Content-Type': f'multipart/form-data; boundary={b}'})
    return json.load(urllib.request.urlopen(req, timeout=120))['data']['downloadUrl']


NO_BRAND = 'generic, unbranded design: no manufacturer logos, no badges, no readable text, no number plate'

CAR = ('A clean 3D studio product render of a {what}, pearl white paint, front three-quarter view from slightly above, '
       'soft studio lighting with a soft contact shadow, ' + NO_BRAND + ', isolated on a transparent background, whole vehicle in frame, centred.')
CARS = {
    'car_hatchback': 'modern compact five-door hatchback (like a typical Malaysian city car)',
    'car_sedan': 'modern four-door compact sedan',
    'car_suv': 'modern compact SUV crossover',
    'car_mpv': 'modern seven-seat family MPV',
    'car_coupe': 'sleek two-door sports coupe',
    'car_pickup': 'modern double-cab pickup truck',
    'car_bike': 'modern naked sport motorcycle (side three-quarter view)',
}

BADGE = ('A collectible hard-enamel lapel pin badge for a car community app, glossy enamel with a polished gold metal rim and fine raised metal lines, '
         'red, black and white enamel palette matching the TT Spot brand in the reference, slight 3D depth, soft studio light, front view, '
         'isolated on a transparent background, centred, no text, no letters, no numbers. The pin shows: ')
BADGES = {
    'badge_car_of_week': 'a gold trophy cup with a small sports car silhouette in front of it, laurel leaves around, round pin',
    'badge_convoy_captain': 'three small cars driving in a line along a curving road with a captain star above, shield-shaped pin',
    'badge_explorer': 'a compass rose with a small map pin in the centre, round pin',
    'badge_first_meet': 'two small cars parked nose to nose with a little sparkle between them, round pin',
    'badge_first_post': 'a retro camera with a flash burst, round pin',
    'badge_garage_open': 'a garage with its roller door half open and a car inside, house-shaped pin',
    'badge_guide_writer': 'a folded road map with a pencil across it, round pin',
    'badge_organiser': 'a red megaphone with sound waves, round pin',
    'badge_popular': 'a big star surrounded by small hearts, star-shaped pin',
    'badge_regular': 'a calendar page covered in small check marks, round pin',
    'badge_spotter': 'a pair of binoculars with a small car reflected in the lenses, round pin',
    'badge_tt_regular': 'a glass of teh tarik (pulled milk tea) with foam and a little steam, round pin',
}

ICON = ('A single glossy 3D app icon object in a soft, rounded, playful 3D style like the reference emoji art, bright clean colours, '
        'soft studio light, isolated on a transparent background, centred, no text, no letters, no logos. The object: ')
ICONS = {
    'kind_cafe': 'a takeaway coffee cup with a small car silhouette printed on it and steam',
    'kind_mamak': 'a glass of teh tarik with foam on a small round mamak table',
    'kind_carpark': 'a blue parking sign with a white letter-free car silhouette on it on a short pole',
    'kind_route': 'a winding mountain road curving up a small green hill',
    'kind_circuit': 'a checkered racing flag crossed with a red-and-white kerb segment',
    'kind_mall': 'a small modern shopping mall building with a glass front',
    'kind_workshop': 'a car on a hydraulic lift with a wrench beside it',
    'kind_tyres': 'a stack of two tyres with a shiny alloy rim on top',
    'kind_bodyshop': 'a spray paint gun spraying a red paint swirl',
    'kind_audio': 'a car subwoofer speaker with sound waves',
    'kind_accessories': 'a performance steering wheel with a gear shift knob beside it',
    'kind_detailing': 'a polishing machine with sparkles over a glossy car panel',
    'kind_carwash': 'a car under soap foam and water drops with a sponge',
    'kind_other': 'a red map pin marker',
    'coin_points': 'a thick gold coin with a raised red checkered flag emblem in the centre, slight tilt, shiny rim',
    'prize_voucher': 'a red and white paper voucher ticket with a perforated edge and a star, slightly curled',
    'prize_merch': 'a black baseball cap and a folded black t-shirt with a small red stripe',
    'prize_gift': 'a red gift box with a white satin ribbon and bow',
}

CREST = ('A car-club crest emblem, flat-shaded vector-style badge with subtle depth and a thin metallic outline, '
         'symmetrical, bold and clean, isolated on a transparent background, centred, no text, no letters. The crest: ')
CRESTS = {
    'crest_1': 'a red shield with a white steering wheel',
    'crest_2': 'black spread wings around a silver piston, gold accents',
    'crest_3': 'a round blue emblem with a white turbocharger',
    'crest_4': 'a green shield with a white mountain road and a small car',
    'crest_5': 'a purple hexagon with crossed silver wrenches',
    'crest_6': 'an orange round emblem with a white lightning bolt through a wheel',
    'crest_7': 'a black shield with a red-and-white checkered band across it',
    'crest_8': 'a teal laurel wreath around a white spark plug',
}

COVER = ('A realistic, cinematic smartphone photo for a Malaysian car-community app, wide 16:9, no readable text or signage, '
         'no logos, no number plates, no close-up faces: ')
COVERS = {
    'pcover_workshop': 'a clean modern car workshop in Malaysia, a car raised on a lift, tools neatly on the wall, bright lighting',
    'pcover_detailing': 'a detailer polishing a glossy black car in a clean detailing studio with LED light panels reflecting on the paint',
    'pcover_tyres': 'a tyre and rim shop with rows of alloy wheels and tyres on display racks',
    'pcover_bodyshop': 'a painter in a white protective suit spraying primer on a single loose car door panel on a stand in a clean white paint booth; no whole car in view',
    'pcover_audio': 'a car interior at night with a glowing custom audio install, subwoofers in the boot lit with LEDs',
    'pcover_accessories': 'a car parts and accessories shop with steering wheels, shift knobs and car care products on shelves',
    'pcover_carwash': 'a car covered in thick white snow foam at a Malaysian car wash, water spray, sunny',
    'pcover_cafe': 'a cosy car-themed café interior with a latte on a wooden counter, framed abstract racing-stripe art on the wall and a chrome wheel rim as decor; no cars in view',
}


def run(jobs):
    tasks = {}
    for k, (prompt, refs, bg, ar) in jobs.items():
        if os.path.exists(os.path.join(OUT, k + '.png')):
            print('skip (exists)', k, flush=True)
            continue
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


if __name__ == '__main__':
    only = set(sys.argv[1:])
    car = upload(os.path.join(REPO, 'assets/cards/c1.jpg'))
    fluent = upload(os.path.join(REPO, 'assets/art/coffee.png'))
    box = upload(os.path.join(REPO, 'assets/titi/box_closed.png'))
    jobs = {}
    for k, what in CARS.items():
        jobs[k] = (CAR.format(what=what), [box], 'transparent', '4:3')
    for k, p in BADGES.items():
        jobs[k] = (BADGE + p, [box], 'transparent', '1:1')
    for k, p in ICONS.items():
        jobs[k] = (ICON + p, [fluent], 'transparent', '1:1')
    for k, p in CRESTS.items():
        jobs[k] = (CREST + p, [box], 'transparent', '1:1')
    for k, p in COVERS.items():
        jobs[k] = (COVER + p, [car], None, '16:9')
    if only:
        jobs = {k: v for k, v in jobs.items() if k in only}
    run(jobs)

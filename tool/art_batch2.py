"""Second art batch: empty-state TiTi poses, TiTi default avatars, default event
covers and a club banner, all via Kie GPT Image 2 image-to-image.

  python tool/art_batch2.py         # creates every task, waits, downloads into tool/titi_gen/batch2/

Needs ~/.supabase/ttspot-kie-key.txt. Poses/avatars use the card art + a clean
TiTi render as references (logo on the LEFT foot only, two legs); covers use the
generated night-meet photo as the style reference.
"""
import json, os, sys, time, uuid, urllib.request

KIE = open(os.path.expanduser('~/.supabase/ttspot-kie-key.txt')).read().strip()
ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, 'titi_gen', 'batch2')
os.makedirs(OUT, exist_ok=True)
REPO = os.path.dirname(ROOT)


def post_json(url, body):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={'Authorization': f'Bearer {KIE}', 'Content-Type': 'application/json'})
    return json.load(urllib.request.urlopen(req, timeout=60))


def get_json(url):
    return json.load(urllib.request.urlopen(urllib.request.Request(url, headers={'Authorization': f'Bearer {KIE}'}), timeout=60))


def upload(local):
    mime = 'image/png' if local.endswith('.png') else 'image/jpeg'
    b = uuid.uuid4().hex
    data = open(local, 'rb').read()
    body = (f'--{b}\r\nContent-Disposition: form-data; name="uploadPath"\r\n\r\nttspot/titi\r\n--{b}\r\nContent-Disposition: form-data; name="file"; filename="{os.path.basename(local)}"\r\nContent-Type: {mime}\r\n\r\n').encode() + data + f'\r\n--{b}--\r\n'.encode()
    req = urllib.request.Request('https://kieai.redpandaai.co/api/file-stream-upload', data=body, headers={'Authorization': f'Bearer {KIE}', 'Content-Type': f'multipart/form-data; boundary={b}'})
    return json.load(urllib.request.urlopen(req, timeout=120))['data']['downloadUrl']


LOOK = ("TiTi, the plush mascot in the reference images: a red-and-white striped traffic-cone plush with silver reflective bands, a cute face with rosy cheeks, "
        "round black felt mitten hands, a black 'DRIVE SAFE' sash with a small white house icon. "
        "ANATOMY, follow strictly: exactly TWO short stubby legs, sitting, one leg on each side, each leg ends in exactly ONE big round foot seen from the sole; "
        "never duplicate a foot, no extra limbs, exactly two arms. "
        "The sole of the foot on the VIEWER'S LEFT shows the white TT Spot logo (stylised white 'TT' with a small red checkered flag and the small word 'TTSPOT' under it); "
        "the other sole is plain black felt. Detailed soft felt texture, crisp 3D plush render, soft studio light, centred, full body, "
        "transparent background, nothing else in frame, no text other than DRIVE SAFE and the foot logo. Pose: ")

POSES = {
    'sleeping': 'fast asleep leaning back, eyes closed, a small "z z" is NOT drawn; a tiny pillow behind him, peaceful smile',
    'binoculars': 'looking through black binoculars, searching the horizon, curious',
    'chat': 'holding up a big white speech bubble with three dots in it, friendly smile',
    'trophy': 'holding a shiny gold trophy cup above his head, proud',
    'calendar': 'holding a small red desk calendar page, thinking, one hand on his chin',
    'heart': 'hugging a big soft red heart pillow, happy eyes closed',
    'voucher': 'holding up a red and white paper voucher ticket with a star on it, excited',
    'bell': 'ringing a small golden hand bell, cheerful',
    'flag': 'waving a black-and-white checkered racing flag, excited',
    'wrench': 'holding a big chrome wrench over his shoulder like a mechanic, confident grin',
    'stop': 'holding a small round red stop sign in front of him, serious but cute',
    'clipboard': 'holding a clipboard with a simple floor plan sketch, pencil in the other hand, focused',
}

AVATAR = ("A round profile picture: head-and-shoulders close-up of TiTi, the plush traffic-cone mascot from the reference images (same face, stripes and sash), "
          "centred, looking at the camera, on a flat solid {bg} background filling the whole square, soft studio light, crisp 3D plush render, no text. He is wearing ")
AVATARS = {
    'a1': ('deep red', 'a white full-face racing helmet with the visor up'),
    'a2': ('charcoal grey', 'a black snapback cap turned backwards'),
    'a3': ('royal blue', 'black sunglasses and a cool smirk'),
    'a4': ('orange', 'big black headphones around his neck'),
    'a5': ('teal', 'a knitted grey beanie'),
    'a6': ('purple', 'a white hachimaki headband with a small red circle, JDM style'),
    'a7': ('yellow', 'a pit-crew radio headset with a small microphone'),
    'a8': ('pink', 'a cream bucket hat and a friendly wink'),
}

COVER = ("A realistic, cinematic smartphone photo for a Malaysian car-community app, wide 16:9 composition, no readable number plates, no text, no logos, no people's faces in close-up: ")
COVERS = {
    'cover_meet': 'a night car meet in a Kuala Lumpur car park, rows of tuned cars under warm lights, small groups chatting, wet asphalt reflections',
    'cover_tt': 'three cars parked casually outside a Malaysian mamak stall late at night, friends at plastic tables, neon signs, relaxed vibe',
    'cover_convoy': 'a convoy of five cars driving on a winding Malaysian highway through green hills at golden hour, seen from behind and above',
    'cover_trackday': 'a sports car taking a corner on a racing circuit with red-and-white kerbs, motion blur, bright daylight, pit lane in the distance',
    'cover_charity': 'a friendly daytime car show with families, cars with open bonnets on a grass field, white canopy tents and balloons',
    'cover_official': 'a premium car brand launch event indoors, a new car on a stage under dramatic spotlights, audience silhouettes',
    'banner_club': 'a wide panoramic shot of a car club lined up at a scenic Malaysian lookout at dusk, city lights far below',
}


def run(jobs):
    tasks = {}
    for k, (prompt, refs, bg, ar) in jobs.items():
        inp = {'prompt': prompt, 'input_urls': refs, 'aspect_ratio': ar, 'resolution': '1K'}
        if bg:
            inp['background'] = bg
        try:
            r = post_json('https://api.kie.ai/api/v1/jobs/createTask', {'model': 'gpt-image-2-image-to-image', 'input': inp})
        except Exception as e:
            r = {'code': 'ERR', 'msg': str(e)}
        tasks[k] = (r.get('data') or {}).get('taskId')
        print('task', k, r.get('code'), r.get('msg'), flush=True)
    done = set()
    for _ in range(90):
        time.sleep(12)
        for k, tid in tasks.items():
            if k in done or not tid:
                continue
            d = (get_json(f'https://api.kie.ai/api/v1/jobs/recordInfo?taskId={tid}').get('data') or {})
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
        if len(done) == len([t for t in tasks.values() if t]):
            break
    missing = [k for k in tasks if not os.path.exists(os.path.join(OUT, k + '.png'))]
    print('missing:', missing)


if __name__ == '__main__':
    only = sys.argv[1:]
    card = upload(os.path.join(REPO, 'assets/cards/c1.jpg'))
    good = upload(os.path.join(REPO, 'assets/titi/thumbsup.png'))
    meet = upload(os.path.join(REPO, 'store/play/screenshots/04_meet.png')) if False else None
    jobs = {}
    for k, p in POSES.items():
        jobs['titi_' + k] = (LOOK + p, [card, good], 'transparent', '1:1')
    for k, (bg, gear) in AVATARS.items():
        jobs['avatar_' + k] = (AVATAR.format(bg=bg) + gear + '.', [card, good], None, '1:1')
    for k, p in COVERS.items():
        jobs[k] = (COVER + p, [card], None, '16:9')
    if only:
        jobs = {k: v for k, v in jobs.items() if k in only}
    run(jobs)

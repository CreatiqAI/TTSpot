"""TiTi art generator: renders mascot poses and box art with Kie (GPT Image 2 image-to-image)
from the blind-box card art, then `poll` downloads the results next to this script under titi_gen/.

  python tool/titi_gen.py create   # uploads assets/cards/c1,c3,c4,c6 as references, creates the tasks
  python tool/titi_gen.py poll     # waits and saves <pose>.png (transparent) into tool/titi_gen/

Needs ~/.supabase/ttspot-kie-key.txt (the Kie API key; never commit it). Afterwards trim + square
each PNG to 720 px and drop it into assets/titi/ (see lib/core/theme/titi.dart for the pose names).
"""
import json, sys, time, os, urllib.request, uuid
KIE=open(os.path.expanduser('~/.supabase/ttspot-kie-key.txt')).read().strip()
OUT=os.path.dirname(os.path.abspath(__file__))+'/titi_gen'; os.makedirs(OUT,exist_ok=True)
def post_json(url, body):
    req=urllib.request.Request(url, data=json.dumps(body).encode(), headers={'Authorization':f'Bearer {KIE}','Content-Type':'application/json'})
    return json.load(urllib.request.urlopen(req, timeout=60))
def get_json(url):
    req=urllib.request.Request(url, headers={'Authorization':f'Bearer {KIE}'})
    return json.load(urllib.request.urlopen(req, timeout=60))
def upload(local):
    b=uuid.uuid4().hex; data=open(local,'rb').read()
    body=(f'--{b}\r\nContent-Disposition: form-data; name="uploadPath"\r\n\r\nttspot/titi\r\n--{b}\r\nContent-Disposition: form-data; name="file"; filename="{os.path.basename(local)}"\r\nContent-Type: image/jpeg\r\n\r\n').encode()+data+f'\r\n--{b}--\r\n'.encode()
    req=urllib.request.Request('https://kieai.redpandaai.co/api/file-stream-upload', data=body, headers={'Authorization':f'Bearer {KIE}','Content-Type':f'multipart/form-data; boundary={b}'})
    return json.load(urllib.request.urlopen(req, timeout=120))['data']['downloadUrl']
def create(prompt, refs, ar='1:1', bg=None):
    inp={'prompt':prompt,'input_urls':refs,'aspect_ratio':ar,'resolution':'1K'}
    if bg: inp['background']=bg
    return post_json('https://api.kie.ai/api/v1/jobs/createTask',{'model':'gpt-image-2-image-to-image','input':inp})
if sys.argv[1]=='create':
    refs=[upload(f'assets/cards/c{i}.jpg') for i in (1,3,4,6)]
    print('refs', len(refs))
    ID=("TiTi, the plush mascot in the reference images: a red-and-white striped traffic cone plush with a cute smiling face, "
        "round black plush arms, a black 'DRIVE SAFE' sash, sitting on four black wheels. Keep his exact look, colours and proportions. "
        "Full body, centred, 3D plush render with soft studio light, no text, no logos except the sash, nothing else in the frame, ")
    poses={
     'wave':'waving hello with one arm raised, friendly and welcoming',
     'camera':'holding a black DSLR camera up with both arms as if about to take a photo',
     'magnifier':'peeking through a large magnifying glass, curious, one eye enlarged by the lens',
     'thumbsup':'giving a big thumbs up with both arms, proud and happy',
     'phone':'holding a smartphone and looking at it, typing',
     'gift':'holding a shiny red gift box with a white ribbon in front of him, excited',
     'mappin':'holding a big red map pin marker above his head, pointing somewhere',
     'rolling':'side view driving fast to the right on his wheels, small motion lines behind, determined face',
     'sad':'sad and confused, drooping, a small sweat drop on his head, arms down',
     'celebrate':'jumping in the air cheering with both arms up, tiny confetti pieces around him',
    }
    tasks={}
    for k,p in poses.items():
        try:
            r=create(ID+p+', on a plain pure white background.', refs, '1:1', 'transparent')
        except Exception as e:
            r={'code':'ERR','msg':str(e)}
        if r.get('code')!=200:
            print(k,'retry without background:',r.get('msg'))
            r=create(ID+p+', on a plain pure white background.', refs, '1:1')
        tasks[k]=r; print(k, r.get('code'), (r.get('data') or {}).get('taskId'))
    BOX=("A premium collectible blind box package for the car community brand TT Spot, product render: a glossy deep-red cube box with a white cross ribbon band, "
         "a round black badge on the front with a red 'TT' mark, a subtle black-and-white racing checker stripe along the bottom edge, small 'SERIES 01' text, "
         "the plush cone mascot TiTi from the reference images printed on one side. Three-quarter view, dramatic studio lighting, soft reflections, "
         "on a dark charcoal background, centred, nothing else in frame.")
    tasks['box_closed']=create(BOX, refs, '1:1'); print('box_closed', tasks['box_closed'].get('code'))
    tasks['box_open']=create(BOX.replace('Three-quarter view','The lid burst open at the top with golden light rays and small sparks shooting out, a glowing card silhouette rising from inside; three-quarter view'), refs, '1:1')
    print('box_open', tasks['box_open'].get('code'))
    json.dump({k:(v.get('data') or {}).get('taskId') for k,v in tasks.items()}, open(f'{OUT}/tasks.json','w'), indent=1)
elif sys.argv[1]=='poll':
    tasks=json.load(open(f'{OUT}/tasks.json')); done={}
    for _ in range(45):
        for k,tid in tasks.items():
            if k in done or not tid: continue
            d=(get_json(f'https://api.kie.ai/api/v1/jobs/recordInfo?taskId={tid}').get('data') or {}); st=d.get('state')
            if st=='success':
                url=json.loads(d.get('resultJson') or '{}').get('resultUrls',[None])[0]
                img=urllib.request.urlopen(url, timeout=120).read(); ext='.png' if url.split('?')[0].lower().endswith('.png') else '.jpg'
                open(f'{OUT}/{k}{ext}','wb').write(img); done[k]=url; print('done',k,ext,len(img)//1024,'KB', flush=True)
            elif st=='fail':
                done[k]=None; print('FAIL',k,d.get('failMsg'), flush=True)
        if len(done)==len([t for t in tasks.values() if t]): break
        time.sleep(12)
    print('finished', len(done), 'of', len(tasks))

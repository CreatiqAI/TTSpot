import sys, os
from PIL import Image
for n in sys.argv[1:]:
    if not os.path.exists(n + '.png') or os.path.getsize(n + '.png') == 0:
        print('missing', n); continue
    im = Image.open(n + '.png').convert('RGBA')
    a = im.getchannel('A').point(lambda v: 0 if v < 150 else 255)
    im.putalpha(a)
    im = im.crop(a.getbbox())
    k = 640 / im.width
    im = im.resize((640, round(im.height * k)), Image.LANCZOS)
    im.save(n + '_c.png', optimize=True)
    print(n, im.size, os.path.getsize(n + '_c.png'))

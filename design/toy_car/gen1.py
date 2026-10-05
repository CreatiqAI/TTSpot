import sys, os
sys.path.insert(0, r'C:\Users\Admin\Desktop\Car\tool')
import art_batch4 as k
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
k.OUT = HERE
src = os.path.join(HERE, 'p911.jpg')
Image.open(r'C:\Users\Admin\Desktop\Car\assets\portrait_samples\base.webp').convert('RGB').save(src, quality=92)
ref = k.upload(src)
TAIL = (' Front three-quarter view from slightly above, the nose pointing to the lower left, the whole car visible. '
        'No brand logos, no badges, no letters, no numbers, a blank number plate. No base, no packaging, no ground, no cast shadow. '
        'Soft even studio light. Isolated on a transparent background, centred.')
A = ('Turn the car in the photo into a premium die-cast toy car, like a 1:64 scale collectible miniature: the exact same car model, '
     'the same body shape and wheel design, and exactly the same paint colour as in the photo. Slightly simplified details, a thick glossy '
     'painted metal body, dark tinted plastic windows, simple moulded lights, rubber-look tyres.' + TAIL)
B = ('Turn the car in the photo into a cute chunky toy car in a soft, rounded, playful 3D style: clearly recognisable as the exact same car model '
     'with the same signature shapes (roofline, lights, wheels) and exactly the same paint colour as in the photo, but with shortened, slightly '
     'squashed proportions, bigger wheels, rounded edges and smooth glossy plastic surfaces with few small details.' + TAIL)
print('credits', k.credits())
k.run({'a911': (A, [ref], 'transparent', '1:1'), 'b911': (B, [ref], 'transparent', '1:1')})
print('credits', k.credits())

import sys, os
sys.path.insert(0, r'C:\Users\Admin\Desktop\Car\tool')
import art_batch4 as k
HERE = os.path.dirname(os.path.abspath(__file__))
k.OUT = HERE
ref = k.upload(os.path.join(HERE, 'a911.png'))
def p(car, colour):
    return (f'A premium die-cast toy car, like a 1:64 scale collectible miniature, of a {car}, painted {colour}. '
            'Exactly the same toy style, finish, camera angle, size in frame and lighting as the reference image (which shows a different car): '
            'accurate, recognisable body shape, lights and wheels of that exact car model, slightly simplified details, a thick glossy painted metal body, '
            'dark tinted plastic windows, simple moulded lights, rubber-look tyres. Front three-quarter view from slightly above, the nose pointing to the lower left, '
            'the whole car visible. No brand logos, no badges, no letters, no numbers, a blank number plate. No base, no packaging, no ground, no cast shadow, no glow. '
            'Soft even studio light. Isolated on a transparent background, centred.')
k.run({
  'civic': (p('2008 Honda Civic FD sedan (eighth generation, Asian market four-door)', 'metallic gunmetal grey'), [ref], 'transparent', '1:1'),
  'myvi': (p('2019 Perodua Myvi (third generation Malaysian five-door hatchback)', 'bright electric blue'), [ref], 'transparent', '1:1'),
  'estima': (p('2007 Toyota Estima (third generation MPV, also sold as Previa, with its smooth egg-shaped one-box body)', 'pearl white'), [ref], 'transparent', '1:1'),
})
print('credits', k.credits())

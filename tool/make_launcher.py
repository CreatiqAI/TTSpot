"""TT Spot launcher icon: teh-tarik orange tile with the 3D car. Writes legacy
mipmaps, adaptive foreground/background, and the anydpi-v26 XML."""
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
CAR = os.path.join(ROOT, "assets", "art", "car.png")
BG = (245, 165, 36)        # #F5A524, the TT now orange
BG_DEEP = (230, 140, 20)   # bottom of the gradient
SCRATCH = os.path.join(ROOT, "build")

car = Image.open(CAR).convert("RGBA")


def gradient(size):
    im = Image.new("RGBA", (size, size))
    px = im.load()
    for y in range(size):
        t = y / max(1, size - 1)
        c = tuple(int(BG[i] * (1 - t) + BG_DEEP[i] * t) for i in range(3)) + (255,)
        for x in range(size):
            px[x, y] = c
    return im


def car_layer(size, scale):
    """Car centred on a transparent canvas, with a soft drop shadow."""
    s = int(size * scale)
    c = car.resize((s, s), Image.LANCZOS)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # shadow
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    alpha = c.split()[3]
    sh = Image.new("RGBA", c.size, (0, 0, 0, 90))
    sh.putalpha(alpha.point(lambda a: int(a * 0.5)))
    shadow.paste(sh, ((size - s) // 2, (size - s) // 2 + int(size * 0.03)), sh)
    shadow = shadow.filter(ImageFilter.GaussianBlur(size * 0.03))
    layer = Image.alpha_composite(layer, shadow)
    layer.paste(c, ((size - s) // 2, (size - s) // 2), c)
    return layer


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return m


# ---- legacy full icons (rounded square, transparent corners) ----
legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
master = 1024
tile = Image.alpha_composite(gradient(master), car_layer(master, 0.70))
tile.putalpha(rounded_mask(master, int(master * 0.22)))
os.makedirs(SCRATCH, exist_ok=True)
tile.save(os.path.join(SCRATCH, "icon-preview.png"))
for dpi, px in legacy.items():
    d = os.path.join(RES, f"mipmap-{dpi}")
    os.makedirs(d, exist_ok=True)
    tile.resize((px, px), Image.LANCZOS).save(os.path.join(d, "ic_launcher.png"))

# ---- adaptive layers (108 dp, safe zone is the central 66 %) ----
adaptive = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
fg_master = car_layer(1024, 0.50)  # 50 % of 108 dp = 54 dp, inside the 66 dp safe circle
bg_master = gradient(1024)
for dpi, px in adaptive.items():
    d = os.path.join(RES, f"mipmap-{dpi}")
    fg_master.resize((px, px), Image.LANCZOS).save(os.path.join(d, "ic_launcher_foreground.png"))
    bg_master.resize((px, px), Image.LANCZOS).save(os.path.join(d, "ic_launcher_background.png"))

anydpi = os.path.join(RES, "mipmap-anydpi-v26")
os.makedirs(anydpi, exist_ok=True)
xml = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
"""
for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
    open(os.path.join(anydpi, name), "w", encoding="utf-8", newline="\n").write(xml)

# ---- Android 12+ splash: white, icon centred (icon must be adaptive-sized) ----
v31 = os.path.join(RES, "values-v31")
os.makedirs(v31, exist_ok=True)
open(os.path.join(v31, "styles.xml"), "w", encoding="utf-8", newline="\n").write("""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowSplashScreenBackground">#FFFFFF</item>
        <item name="android:windowSplashScreenAnimatedIcon">@mipmap/ic_launcher</item>
        <item name="android:windowBackground">@drawable/launch_background</item>
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
""")
print("launcher written")

"""TT Spot app icons from the brand logo (assets/TTSpot_logo.png).

Writes: Android legacy mipmaps + adaptive layers + anydpi XML + Android 12
splash style, the iOS AppIcon set, the iOS LaunchImage set, and a cropped
in-app copy at assets/brand/logo.png. Run: python tool/make_launcher.py"""
import json
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
LOGO = os.path.join(ROOT, "assets", "TTSpot_logo.png")
BRAND = os.path.join(ROOT, "assets", "brand")
IOS_ICONS = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
IOS_LAUNCH = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "LaunchImage.imageset")
WHITE = (255, 255, 255, 255)

src = Image.open(LOGO).convert("RGBA")
logo = src.crop(src.getbbox())  # drop the transparent padding


def fit(size, scale, bg=None):
    """Logo centred on a `size`×`size` canvas, longest side = size*scale."""
    canvas = Image.new("RGBA", (size, size), bg or (0, 0, 0, 0))
    w, h = logo.size
    k = size * scale / max(w, h)
    l = logo.resize((max(1, int(w * k)), max(1, int(h * k))), Image.LANCZOS)
    canvas.paste(l, ((size - l.width) // 2, (size - l.height) // 2), l)
    return canvas


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return m


# ---- in-app asset (cropped, transparent) ----
os.makedirs(BRAND, exist_ok=True)
logo.save(os.path.join(BRAND, "logo.png"))

# ---- Android legacy icons: white rounded tile, logo at 78 % ----
master = 1024
tile = fit(master, 0.78, WHITE)
tile.putalpha(rounded_mask(master, int(master * 0.22)))
for dpi, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    d = os.path.join(RES, f"mipmap-{dpi}")
    os.makedirs(d, exist_ok=True)
    tile.resize((px, px), Image.LANCZOS).save(os.path.join(d, "ic_launcher.png"))

# ---- adaptive layers (108 dp canvas, the launcher shows the central 66 %) ----
fg_master = fit(1024, 0.56)                      # logo inside the safe circle
bg_master = Image.new("RGBA", (1024, 1024), WHITE)
for dpi, px in {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}.items():
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

# ---- Android 12+ splash: white, launcher icon centred ----
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

# ---- iOS app icon set (opaque white, logo at 78 %; iOS rounds the corners) ----
ios_master = fit(1024, 0.78, WHITE).convert("RGB")
contents = json.load(open(os.path.join(IOS_ICONS, "Contents.json"), encoding="utf-8"))
for entry in contents["images"]:
    px = int(round(float(entry["size"].split("x")[0]) * int(entry["scale"].rstrip("x"))))
    ios_master.resize((px, px), Image.LANCZOS).save(os.path.join(IOS_ICONS, entry["filename"]))

# ---- iOS launch screen: transparent logo, 160 pt ----
for scale, name in ((1, "LaunchImage.png"), (2, "LaunchImage@2x.png"), (3, "LaunchImage@3x.png")):
    fit(160 * scale, 1.0).save(os.path.join(IOS_LAUNCH, name))

print("icons written from", os.path.relpath(LOGO, ROOT))

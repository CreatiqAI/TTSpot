"""Printable spot stickers: one PNG per recommended spot + one PDF with all of
them. Run: python tool/make_stickers.py   (needs pillow + qrcode, and the
Supabase access token file used by the CLI).

Each sticker's QR is `ttspot://spot/<placeId>/<code>`; the code is derived from
the spot's secret, so re-run after `admin_rotate_sticker()` to reprint."""
import io, json, os, re, subprocess, sys

import qrcode
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "build", "stickers")
CLI = r"C:\Users\Admin\supabase-cli\supabase.exe"
TOKEN_FILE = r"C:\Users\Admin\.supabase\car-meet-access-token.txt"
FONT_BOLD = os.path.join(ROOT, "assets", "fonts", "BarlowCondensed-Bold.ttf")
FONT_SEMI = os.path.join(ROOT, "assets", "fonts", "BarlowCondensed-SemiBold.ttf")
CAR = os.path.join(ROOT, "assets", "art", "car.png")

ORANGE = (245, 165, 36)
INK = (15, 17, 21)

SQL = """
select p.id, p.name, p.kind,
       'ttspot://spot/' || p.id || '/' || public.spot_sticker_code(p.id) as payload
from public.places p where p.recommended order by p.name;
"""


def fetch_spots():
    os.makedirs(OUT, exist_ok=True)
    sql_path = os.path.join(OUT, "_spots.sql")
    io.open(sql_path, "w", encoding="utf-8").write(SQL)
    env = dict(os.environ, SUPABASE_ACCESS_TOKEN=io.open(TOKEN_FILE).read().strip())
    res = subprocess.run([CLI, "db", "query", "--linked", "-f", sql_path], capture_output=True, text=True, env=env, cwd=ROOT)
    m = re.search(r"\{.*\}", res.stdout, re.S)
    if not m:
        sys.exit("query failed:\n" + res.stdout + res.stderr)
    data = json.loads(m.group(0))
    rows = data.get("rows") or data.get("result") or data
    if isinstance(rows, dict):
        rows = rows.get("rows", [])
    return rows


def sticker(row):
    W, H = 1240, 1748  # A6 at 300 dpi
    im = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(im)
    # header
    d.rectangle((0, 0, W, 260), fill=ORANGE)
    f_brand = ImageFont.truetype(FONT_BOLD, 150)
    d.text((70, 45), "TT Spot", font=f_brand, fill=INK)
    car = Image.open(CAR).convert("RGBA").resize((200, 200), Image.LANCZOS)
    im.paste(car, (W - 270, 30), car)
    # title
    f_title = ImageFont.truetype(FONT_BOLD, 96)
    f_small = ImageFont.truetype(FONT_SEMI, 52)
    name = row["name"]
    # wrap the name to the sticker width
    words, lines, cur = name.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if d.textlength(t, font=f_title) > W - 140 and cur:
            lines.append(cur)
            cur = w
        else:
            cur = t
    if cur:
        lines.append(cur)
    y = 310
    for line in lines[:2]:
        d.text((70, y), line, font=f_title, fill=INK)
        y += 105
    d.text((70, y + 6), "CHECK-IN SPOT  ·", font=f_small, fill=(110, 110, 110))
    cjk = r"C:\Windows\Fonts\msyh.ttc"
    if os.path.exists(cjk):
        f_cjk = ImageFont.truetype(cjk, 46)
        d.text((70 + d.textlength("CHECK-IN SPOT  ·  ", font=f_small), y + 6), "打卡点", font=f_cjk, fill=(110, 110, 110))
    # qr
    q = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_H, box_size=10, border=2)
    q.add_data(row["payload"])
    q.make(fit=True)
    qr = q.make_image(fill_color="black", back_color="white").convert("RGB")
    qs = 820
    qr = qr.resize((qs, qs), Image.NEAREST)
    qx, qy = (W - qs) // 2, y + 110
    d.rounded_rectangle((qx - 24, qy - 24, qx + qs + 24, qy + qs + 24), radius=40, outline=INK, width=8)
    im.paste(qr, (qx, qy))
    # footer
    f_foot = ImageFont.truetype(FONT_SEMI, 54)
    f_tiny = ImageFont.truetype(FONT_SEMI, 40)
    fy = qy + qs + 60
    d.text((W // 2, fy), "Scan in the TT Spot app · snap your car · earn points", font=f_foot, fill=INK, anchor="ma")
    d.text((W // 2, fy + 75), "ttspot.my", font=f_tiny, fill=(110, 110, 110), anchor="ma")
    return im


def main():
    rows = fetch_spots()
    if not rows:
        sys.exit("no recommended spots")
    pages = []
    for r in rows:
        im = sticker(r)
        slug = re.sub(r"[^a-z0-9]+", "-", r["name"].lower()).strip("-")
        im.save(os.path.join(OUT, f"{slug}.png"), dpi=(300, 300))
        pages.append(im)
        print("sticker:", r["name"])
    pages[0].save(os.path.join(OUT, "stickers.pdf"), save_all=True, append_images=pages[1:], resolution=300)
    print("pdf:", os.path.join(OUT, "stickers.pdf"), f"({len(pages)} pages)")


if __name__ == "__main__":
    main()

"""Download Fluent Emoji 3D PNGs (MIT) into assets/art/<key>.png."""
import io, os, urllib.request, urllib.parse

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "art")
BASE = "https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/assets/"

# key -> (folder name, snake name, has skin tone default?)
ART = {
    "car": ("Automobile", "automobile", False),
    "coffee": ("Hot beverage", "hot_beverage", False),
    "road": ("Motorway", "motorway", False),
    "flag": ("Chequered flag", "chequered_flag", False),
    "heart_yellow": ("Yellow heart", "yellow_heart", False),
    "trophy": ("Trophy", "trophy", False),
    "parking": ("P button", "p_button", False),
    "racing": ("Racing car", "racing_car", False),
    "mall": ("Department store", "department_store", False),
    "pin": ("Round pushpin", "round_pushpin", False),
    "camera": ("Camera with flash", "camera_with_flash", False),
    "eyes": ("Eyes", "eyes", False),
    "chart": ("Bar chart", "bar_chart", False),
    "map": ("World map", "world_map", False),
    "stopwatch": ("Stopwatch", "stopwatch", False),
    "shield": ("Shield", "shield", False),
    "fire": ("Fire", "fire", False),
    "ghost": ("Ghost", "ghost", False),
    "hug": ("People hugging", "people_hugging", False),
    "repeat": ("Repeat button", "repeat_button", False),
    "megaphone": ("Megaphone", "megaphone", False),
    "star": ("Star", "star", False),
    "party": ("Party popper", "party_popper", False),
    "sparkles": ("Sparkles", "sparkles", False),
    "red_dot": ("Red circle", "red_circle", False),
    "alarm": ("Alarm clock", "alarm_clock", False),
    "speech": ("Speech balloon", "speech_balloon", False),
    "calendar": ("Calendar", "calendar", False),
    "bell": ("Bell", "bell", False),
    "bookmark": ("Bookmark", "bookmark", False),
    "search": ("Magnifying glass tilted left", "magnifying_glass_tilted_left", False),
    "picture": ("Framed picture", "framed_picture", False),
    "ticket": ("Admission tickets", "admission_tickets", False),
    "gift": ("Wrapped gift", "wrapped_gift", False),
    "phone": ("Mobile phone", "mobile_phone", False),
    "coins": ("Coin", "coin", False),
    "wrench": ("Wrench", "wrench", False),
    "rocket": ("Rocket", "rocket", False),
    "wave": ("Waving hand", "waving_hand", True),
    "handshake": ("Handshake", "handshake", True),
    "suv": ("Sport utility vehicle", "sport_utility_vehicle", False),
    "night": ("Night with stars", "night_with_stars", False),
    "compass": ("Compass", "compass", False),
    "locked": ("Locked", "locked", False),
    "pizza": ("Pizza", "pizza", False),
    "thumbs_up": ("Thumbs up", "thumbs_up", True),
    "clock": ("Alarm clock", "alarm_clock", False),
    "wifi_off": ("Prohibited", "prohibited", False),
    "cityscape": ("Cityscape at dusk", "cityscape_at_dusk", False),
    "collision": ("Collision", "collision", False),
    "wrench2": ("Hammer and wrench", "hammer_and_wrench", False),
    "gear": ("Gear", "gear", False),
    "tada": ("Confetti ball", "confetti_ball", False),
    "medal": ("Sports medal", "sports_medal", False),
    "first": ("1st place medal", "1st_place_medal", False),
    "police": ("Police car light", "police_car_light", False),
    "fuel": ("Fuel pump", "fuel_pump", False),
    "kiss": ("Face blowing a kiss", "face_blowing_a_kiss", False),
    "cool": ("Smiling face with sunglasses", "smiling_face_with_sunglasses", False),
    "mailbox": ("Envelope with arrow", "envelope_with_arrow", False),
    "check": ("Check mark button", "check_mark_button", False),
}

os.makedirs(OUT, exist_ok=True)
ok, bad = [], []
for key, (folder, snake, tone) in ART.items():
    dest = os.path.join(OUT, f"{key}.png")
    if os.path.exists(dest) and os.path.getsize(dest) > 1000:
        ok.append(key)
        continue
    if tone:
        rel = f"{folder}/Default/3D/{snake}_3d_default.png"
    else:
        rel = f"{folder}/3D/{snake}_3d.png"
    url = BASE + urllib.parse.quote(rel)
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            data = r.read()
        if len(data) < 500:
            raise RuntimeError("tiny")
        with open(dest, "wb") as f:
            f.write(data)
        ok.append(key)
    except Exception as e:
        bad.append((key, rel, str(e)[:60]))

print("ok:", len(ok))
for b in bad:
    print("FAIL", b)
